-- =============================================================================
-- 20260921000004_music_settings_quote_tolerant.sql
-- -----------------------------------------------------------------------------
-- Müzik anahtarlarının OKUYUCULARINI tırnağa dayanıklı yapar.
--
-- ## Sorun
--
-- `app_settings.value` jsonb. Admin panelindeki müzik anahtarları istemciden
-- `'"true"'` (çift tırnaklı) yazıyordu. PostgREST Dart string'ini zaten JSON
-- string olarak kodladığı için bu, jsonb'de TIRNAKLI metin bırakır:
-- `value #>> '{}'` → `"true"`. Okuyucular bunu doğrudan `::boolean` /
-- `::integer`'a çeviriyordu ve çevrim `invalid input syntax` ile patlıyordu.
-- Sonuç: admin bir müzik anahtarına İLK dokunduğunda katalog araması,
-- başvuru RPC'si, gönderi/hikaye tetikleyicisi ve misafir Keşfet akışı
-- (music_flag kullanıyor) hata verecekti.
--
-- Canlıda henüz bozuk değer YOK (2026-09-21 itibarıyla hiçbir anahtara
-- dokunulmamış); istemci aynı sürümde düzeltildi. Bu migration yine de
-- okuyucuyu sağlamlaştırıyor: eski bir istemci sürümü hâlâ tırnaklı
-- yazabilir, ve bir ayar okuyucusu hiçbir koşulda sayfayı düşürmemeli.
--
-- Desen `public.leaderboard_setting` ile aynı: çevrim yerine metin karşılaştırma,
-- tanınmayan değerde varsayılana düşme — ASLA istisna fırlatmaz.
-- =============================================================================

begin;

SET LOCAL lock_timeout = '10s';

-- Ayarın çıplak metni: tırnak ve boşluklardan arındırılmış, boşsa NULL.
CREATE OR REPLACE FUNCTION public.music_setting_text(p_key text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT NULLIF(btrim(s.value #>> '{}', E'" \t\r\n'), '')
  FROM public.app_settings s
  WHERE s.key = p_key;
$fn$;
REVOKE ALL ON FUNCTION public.music_setting_text(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.music_setting_text(text)
  TO anon, authenticated, service_role;

-- İmza ve davranış aynı; yalnızca çevrim istisna fırlatmayan karşılaştırmaya
-- dönüştü. Bu fonksiyonu çağıran her şey (music_settings, music_search_catalog,
-- music_submit_track, music_attach_guard, public_explore_feed) otomatik olarak
-- düzelir.
CREATE OR REPLACE FUNCTION public.music_flag(p_key text, p_default boolean DEFAULT false)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN lower(t) IN ('true', 't', '1', 'yes', 'on') THEN true
    WHEN lower(t) IN ('false', 'f', '0', 'no', 'off') THEN false
    ELSE p_default
  END
  FROM (SELECT public.music_setting_text(p_key) AS t) AS x;
$fn$;
REVOKE ALL ON FUNCTION public.music_flag(text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.music_flag(text, boolean)
  TO anon, authenticated, service_role;

-- Yükleme sınırı (MB). Sayı değilse ya da makul aralık dışındaysa 10.
CREATE OR REPLACE FUNCTION public.music_max_upload_mb()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN t ~ '^[0-9]{1,3}$' AND t::integer BETWEEN 1 AND 50 THEN t::integer
    ELSE 10
  END
  FROM (SELECT public.music_setting_text('music_max_upload_mb') AS t) AS x;
$fn$;
REVOKE ALL ON FUNCTION public.music_max_upload_mb() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.music_max_upload_mb()
  TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.music_settings()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object(
    'feature',       public.music_flag('music_feature_enabled', true),
    'catalog',       public.music_flag('music_catalog_enabled', true),
    'device_add',    public.music_flag('music_device_add_enabled', true),
    'attach',        public.music_flag('music_attach_enabled', true),
    'artist_upload', public.music_flag('music_artist_uploads_enabled', false),
    'max_upload_mb', public.music_max_upload_mb()
  );
$fn$;
REVOKE ALL ON FUNCTION public.music_settings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.music_settings()
  TO anon, authenticated, service_role;

-- music_submit_track: gövde 20260920000007 ile aynı; yalnızca boyut sınırı
-- artık çevrim yapmayan okuyucudan geliyor.
CREATE OR REPLACE FUNCTION public.music_submit_track(
  p_title text,
  p_artist text,
  p_genre text,
  p_storage_path text,
  p_public_url text,
  p_duration_ms integer,
  p_size_bytes bigint,
  p_rights_confirmed boolean
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid     uuid := auth.uid();
  v_id      uuid;
  v_max_mb  integer;
  v_pending integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:unauthenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.music_flag('music_feature_enabled', true)
     OR NOT public.music_flag('music_artist_uploads_enabled', false) THEN
    RAISE EXCEPTION 'APP:music_uploads_closed' USING ERRCODE = '42501';
  END IF;

  IF COALESCE(p_rights_confirmed, false) = false THEN
    RAISE EXCEPTION 'APP:rights_not_confirmed' USING ERRCODE = '22023';
  END IF;

  IF NULLIF(btrim(COALESCE(p_title, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_artist, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_public_url, '')), '') IS NULL THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;

  v_max_mb := public.music_max_upload_mb();

  IF COALESCE(p_size_bytes, 0) > v_max_mb::bigint * 1024 * 1024 THEN
    RAISE EXCEPTION 'APP:file_too_large' USING ERRCODE = '22023';
  END IF;

  -- Kuyruk doldurmayı engelle: aynı anda en çok 5 bekleyen başvuru.
  SELECT count(*) INTO v_pending
  FROM public.music_track_submissions
  WHERE user_id = v_uid AND status = 'pending';

  IF v_pending >= 5 THEN
    RAISE EXCEPTION 'APP:too_many_pending' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.music_track_submissions
    (user_id, title, artist, genre, storage_path, public_url,
     duration_ms, size_bytes, rights_confirmed)
  VALUES (
    v_uid,
    btrim(p_title),
    btrim(p_artist),
    NULLIF(btrim(COALESCE(p_genre, '')), ''),
    p_storage_path,
    p_public_url,
    p_duration_ms,
    p_size_bytes,
    true
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$fn$;
REVOKE ALL ON FUNCTION public.music_submit_track(
  text, text, text, text, text, integer, bigint, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.music_submit_track(
  text, text, text, text, text, integer, bigint, boolean) TO authenticated;

commit;

NOTIFY pgrst, 'reload schema';
