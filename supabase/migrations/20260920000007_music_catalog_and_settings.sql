-- =============================================================================
-- 20260920000007_music_catalog_and_settings.sql
-- -----------------------------------------------------------------------------
-- "Müziğim" özelliğinin sunucu tarafı: tek bir müzik kataloğu, yerel
-- sanatçıların şarkı başvuruları ve özelliği parça parça açıp kapatan
-- admin anahtarları.
--
-- ## Neden yeni bir katalog tablosu
--
-- Şarkılar bugüne kadar `okey_sound_assets` içinde `music:<uuid>` anahtarıyla,
-- yani ses EFEKTLERİYLE aynı tabloda duruyordu (bkz. 20260901000013). O tasarım
-- tek amaç için doğruydu: Okey masasının fon müziği. Artık müziğin sanatçısı,
-- türü, süresi, kimin yüklediği ve yayında olup olmadığı gibi alanları var;
-- bunlar bir "ses efekti anahtarı" tablosuna sığmıyor.
--
-- GERİYE DÖNÜK UYUM SÖZLEŞMESİ: `okey_list_music()` fonksiyonunun DÖNÜŞ ŞEKLİ
-- (sound_key, public_url, display_name) aynen korunur; yalnızca okuduğu yer
-- değişir. Böylece OkeySoundService ve Okey admin sekmesi tarafında TEK SATIR
-- Dart değişmeden çalışmaya devam eder. Eski satırlar okunup yeni tabloya
-- kopyalanır ama SİLİNMEZ — canlı veritabanında geri alınamaz bir şey yapmamak
-- için kasıtlı olarak orada bırakılırlar.
--
-- ## Anahtarlar neden hem burada hem istemcide
--
-- `app_settings` bayrakları arayüzü gizlemek için yeterli DEĞİLDİR; istemciyi
-- kurcalayan biri kapalı bir özelliği açabilirdi. Bu yüzden her bayrağın
-- sunucu tarafında bir karşılığı var: katalog araması bayrak kapalıyken boş
-- döner, başvuru RPC'si reddeder. `explore_public_access` ile aynı desen.
-- =============================================================================

begin;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) music_catalog — uygulamanın TEK müzik kataloğu
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.music_catalog (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title        text NOT NULL,
  artist       text,
  genre        text,
  storage_path text,
  public_url   text NOT NULL,
  duration_ms  integer,
  -- 'admin': admin panelinden yüklendi. 'artist': yerel sanatçı başvurusu
  -- onaylandı. Katalogda ikisi yan yana durur, ayrımı yalnızca rozet için.
  source       text NOT NULL DEFAULT 'admin',
  submitted_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

DO $mc$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.music_catalog'::regclass
      AND conname = 'music_catalog_source_check'
  ) THEN
    ALTER TABLE public.music_catalog
      ADD CONSTRAINT music_catalog_source_check
      CHECK (source IN ('admin', 'artist'));
  END IF;
END
$mc$;

COMMENT ON TABLE public.music_catalog IS
  'Cizre Radyo kataloğu. Okey fon müziği de buradan beslenir (okey_list_music).';

CREATE INDEX IF NOT EXISTS idx_music_catalog_active
  ON public.music_catalog (is_active, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_music_catalog_genre
  ON public.music_catalog (genre) WHERE is_active;

-- Arama: başlık + sanatçı üzerinde trigram. Katalog küçükken ILIKE de yeterdi
-- ama ürün aramasında (20260907150001) aynı deseni kurduğumuz için burada da
-- baştan indeksliyoruz; sonradan yavaşlayıp fark etmek zor.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;

CREATE INDEX IF NOT EXISTS idx_music_catalog_search
  ON public.music_catalog
  USING gin ((COALESCE(title, '') || ' ' || COALESCE(artist, '')) extensions.gin_trgm_ops);

ALTER TABLE public.music_catalog ENABLE ROW LEVEL SECURITY;

-- Tabloya doğrudan erişim yok: her şey RPC üzerinden. Böylece bayrak kapalıyken
-- istemci tabloyu doğrudan okuyup kapıyı atlayamaz.
REVOKE ALL ON public.music_catalog FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.music_catalog TO service_role;

-- -----------------------------------------------------------------------------
-- 2) Eski şarkıları yeni kataloğa taşı (kopyalar, silmez)
-- -----------------------------------------------------------------------------
INSERT INTO public.music_catalog (title, public_url, storage_path, source)
SELECT
  COALESCE(NULLIF(trim(a.display_name), ''), 'Şarkı'),
  a.public_url,
  a.storage_path,
  'admin'
FROM public.okey_sound_assets AS a
WHERE (a.sound_key LIKE 'music:%' OR a.sound_key = 'background_music')
  AND COALESCE(a.public_url, '') <> ''
  AND NOT EXISTS (
    SELECT 1 FROM public.music_catalog c WHERE c.public_url = a.public_url
  );

-- -----------------------------------------------------------------------------
-- 3) okey_list_music — AYNI dönüş şekli, yeni kaynak
--
-- Bilerek hiçbir bayrağa bakmıyor: bu fonksiyon Okey masasının ve yan menüdeki
-- plak kartının fon müziğini besliyor. "Cizre Radyo kataloğu" anahtarı yeni
-- Müziğim ekranındaki arama yüzeyini yönetir, fon müziğini susturmak onun işi
-- değil — admin bir şarkıyı gerçekten durdurmak isterse onu pasife alır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_list_music()
RETURNS TABLE(sound_key text, public_url text, display_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT ('music:' || c.id::text), c.public_url, c.title
  FROM public.music_catalog AS c
  WHERE c.is_active
  ORDER BY c.title NULLS LAST, c.id;
$fn$;
REVOKE ALL ON FUNCTION public.okey_list_music() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_list_music() TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) admin_okey_add_music — imza aynı, hedef tablo yeni
--
-- Okey admin sekmesindeki "şarkı ekle" düğmesi bu imzayı çağırıyor; imzayı
-- korumak o ekranı değiştirmeden çalışır tutuyor.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_okey_add_music(
  p_storage_path text,
  p_public_url text,
  p_display_name text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(COALESCE(p_public_url, '')), '') IS NULL THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.music_catalog (title, public_url, storage_path, source)
  VALUES (
    COALESCE(NULLIF(trim(COALESCE(p_display_name, '')), ''), 'Şarkı'),
    p_public_url,
    p_storage_path,
    'admin'
  )
  RETURNING id INTO v_id;

  RETURN 'music:' || v_id::text;
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_okey_add_music(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_add_music(text, text, text)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 5) admin_okey_clear_sound — müzik anahtarlarını yeni tablodan siler
--
-- Okey admin sekmesindeki silme düğmesi `music:<uuid>` anahtarıyla geliyor.
-- Efekt anahtarları için eski davranış aynen korunur.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_okey_clear_sound(p_sound_key text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_path text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_sound_key LIKE 'music:%' THEN
    DELETE FROM public.music_catalog
    WHERE id = NULLIF(substring(p_sound_key FROM 7), '')::uuid
    RETURNING storage_path INTO v_path;
    RETURN v_path;
  END IF;

  DELETE FROM public.okey_sound_assets
  WHERE sound_key = p_sound_key
  RETURNING storage_path INTO v_path;

  RETURN v_path;
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_okey_clear_sound(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_clear_sound(text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 6) Özellik anahtarları
-- -----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('music_feature_enabled', '"true"',
   'Müziğim özelliği açık mı? Kapalıyken yan menü girişi ve tüm müzik düğmeleri gizlenir.'),
  ('music_catalog_enabled', '"true"',
   'Cizre Radyo kataloğu ve içindeki arama açık mı?'),
  ('music_device_add_enabled', '"true"',
   'Kullanıcı kendi cihazındaki dosyaları kitaplığına ekleyebilir mi? (Sunucuya hiçbir şey gitmez, yalnızca arayüz kapısıdır.)'),
  ('music_attach_enabled', '"true"',
   'Gönderi ve hikayeye müzik eklenebilir mi? Kapatılınca mevcut gönderilerdeki müzik de susar.'),
  ('music_artist_uploads_enabled', '"true"',
   'Yerel sanatçılar şarkı başvurusu yapabilir mi? Kapatmak onaylanmış şarkıları etkilemez.'),
  ('music_max_upload_mb', '"10"',
   'Sanatçı başvurusunda dosya başına üst sınır (MB).')
ON CONFLICT (key) DO NOTHING;

-- Bayrağı tek yerden okuyan yardımcı. `explore_public_access` ile aynı
-- ayrıştırma: değer jsonb ve konvansiyon gereği JSON string ("true").
CREATE OR REPLACE FUNCTION public.music_flag(p_key text, p_default boolean DEFAULT false)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT COALESCE(
    (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
       FROM public.app_settings s WHERE s.key = p_key),
    p_default
  );
$fn$;
REVOKE ALL ON FUNCTION public.music_flag(text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.music_flag(text, boolean)
  TO anon, authenticated, service_role;

-- İstemci tüm anahtarları TEK çağrıda alır; her ekran ayrı ayrı sorgulamasın.
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
    'max_upload_mb', COALESCE(
      (SELECT NULLIF(btrim(s.value #>> '{}'), '')::integer
         FROM public.app_settings s WHERE s.key = 'music_max_upload_mb'),
      10)
  );
$fn$;
REVOKE ALL ON FUNCTION public.music_settings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.music_settings()
  TO anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7) music_search_catalog — Cizre Radyo araması
--
-- Sunucu tarafı kapı: özellik ya da katalog anahtarı kapalıysa BOŞ döner.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.music_search_catalog(
  p_query text DEFAULT NULL,
  p_genre text DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  title text,
  artist text,
  genre text,
  public_url text,
  duration_ms integer,
  source text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_q      text    := NULLIF(btrim(COALESCE(p_query, '')), '');
  v_genre  text    := NULLIF(btrim(COALESCE(p_genre, '')), '');
BEGIN
  IF NOT public.music_flag('music_feature_enabled', true)
     OR NOT public.music_flag('music_catalog_enabled', true) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT c.id, c.title, c.artist, c.genre, c.public_url,
         c.duration_ms, c.source, c.created_at
  FROM public.music_catalog AS c
  WHERE c.is_active
    AND (v_genre IS NULL OR c.genre = v_genre)
    AND (
      v_q IS NULL
      OR (COALESCE(c.title, '') || ' ' || COALESCE(c.artist, '')) ILIKE '%' || v_q || '%'
    )
  ORDER BY
    -- Aramada isabet sırası: başlığı tam eşleşen önce gelsin.
    CASE WHEN v_q IS NOT NULL AND c.title ILIKE v_q || '%' THEN 0 ELSE 1 END,
    c.title NULLS LAST
  LIMIT v_limit OFFSET v_offset;
END;
$fn$;
REVOKE ALL ON FUNCTION public.music_search_catalog(text, text, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.music_search_catalog(text, text, integer, integer)
  TO authenticated;

-- Tür süzgeci için katalogda gerçekten var olan türler.
CREATE OR REPLACE FUNCTION public.music_catalog_genres()
RETURNS TABLE (genre text, track_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT c.genre, count(*)
  FROM public.music_catalog AS c
  WHERE c.is_active AND NULLIF(btrim(COALESCE(c.genre, '')), '') IS NOT NULL
  GROUP BY c.genre
  ORDER BY count(*) DESC, c.genre;
$fn$;
REVOKE ALL ON FUNCTION public.music_catalog_genres() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.music_catalog_genres() TO authenticated;

-- -----------------------------------------------------------------------------
-- 8) music_track_submissions — yerel sanatçı başvuruları
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.music_track_submissions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title            text NOT NULL,
  artist           text NOT NULL,
  genre            text,
  storage_path     text NOT NULL,
  public_url       text NOT NULL,
  duration_ms      integer,
  size_bytes       bigint,
  -- Başvuru anında kullanıcının onayladığı hak beyanı. Telif şikâyeti gelirse
  -- kimin neyi beyan ettiğini göstermek için kalıcı olarak saklanır.
  rights_confirmed boolean NOT NULL DEFAULT false,
  status           text NOT NULL DEFAULT 'pending',
  reject_reason    text,
  reviewed_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at      timestamptz,
  catalog_id       uuid REFERENCES public.music_catalog(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

DO $ms$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.music_track_submissions'::regclass
      AND conname = 'music_submissions_status_check'
  ) THEN
    ALTER TABLE public.music_track_submissions
      ADD CONSTRAINT music_submissions_status_check
      CHECK (status IN ('pending', 'approved', 'rejected'));
  END IF;
END
$ms$;

CREATE INDEX IF NOT EXISTS idx_music_submissions_status
  ON public.music_track_submissions (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_music_submissions_user
  ON public.music_track_submissions (user_id, created_at DESC);

ALTER TABLE public.music_track_submissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.music_track_submissions FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.music_track_submissions TO service_role;

-- -----------------------------------------------------------------------------
-- 9) music_submit_track — başvuru gönder
-- -----------------------------------------------------------------------------
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

  v_max_mb := COALESCE(
    (SELECT NULLIF(btrim(s.value #>> '{}'), '')::integer
       FROM public.app_settings s WHERE s.key = 'music_max_upload_mb'),
    10);

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

-- Kullanıcı kendi başvurularını ve red sebebini görür.
CREATE OR REPLACE FUNCTION public.music_my_submissions()
RETURNS TABLE (
  id uuid,
  title text,
  artist text,
  genre text,
  status text,
  reject_reason text,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT s.id, s.title, s.artist, s.genre, s.status, s.reject_reason, s.created_at
  FROM public.music_track_submissions AS s
  WHERE s.user_id = auth.uid()
  ORDER BY s.created_at DESC
  LIMIT 50;
$fn$;
REVOKE ALL ON FUNCTION public.music_my_submissions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.music_my_submissions() TO authenticated;

-- -----------------------------------------------------------------------------
-- 10) Admin: başvuru kuyruğu ve katalog yönetimi
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_music_list_submissions(
  p_status text DEFAULT 'pending',
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  username text,
  title text,
  artist text,
  genre text,
  public_url text,
  duration_ms integer,
  size_bytes bigint,
  status text,
  reject_reason text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT s.id, s.user_id, pr.username, s.title, s.artist, s.genre,
         s.public_url, s.duration_ms, s.size_bytes, s.status,
         s.reject_reason, s.created_at
  FROM public.music_track_submissions AS s
  LEFT JOIN public.profiles pr ON pr.id = s.user_id
  WHERE s.status = COALESCE(NULLIF(btrim(COALESCE(p_status, '')), ''), 'pending')
  ORDER BY s.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_music_list_submissions(text, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_music_list_submissions(text, integer)
  TO authenticated;

-- Onay: başvuru kataloğa geçer. Red: sebep yazılır, dosya depoda kalır
-- (istemci silmeyi üstlenir; burada silinirse red geri alınamaz olurdu).
CREATE OR REPLACE FUNCTION public.admin_music_review_submission(
  p_id uuid,
  p_approve boolean,
  p_reason text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_row public.music_track_submissions%ROWTYPE;
  v_catalog_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.music_track_submissions
  WHERE id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'APP:already_reviewed' USING ERRCODE = '22023';
  END IF;

  IF COALESCE(p_approve, false) THEN
    INSERT INTO public.music_catalog
      (title, artist, genre, storage_path, public_url, duration_ms,
       source, submitted_by)
    VALUES (
      v_row.title, v_row.artist, v_row.genre, v_row.storage_path,
      v_row.public_url, v_row.duration_ms, 'artist', v_row.user_id
    )
    RETURNING id INTO v_catalog_id;

    UPDATE public.music_track_submissions
    SET status = 'approved',
        catalog_id = v_catalog_id,
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        reject_reason = NULL
    WHERE id = p_id;

    RETURN v_catalog_id;
  END IF;

  UPDATE public.music_track_submissions
  SET status = 'rejected',
      reject_reason = NULLIF(btrim(COALESCE(p_reason, '')), ''),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  WHERE id = p_id;

  RETURN NULL;
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_music_review_submission(uuid, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_music_review_submission(uuid, boolean, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_music_list_catalog(
  p_query text DEFAULT NULL,
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  id uuid,
  title text,
  artist text,
  genre text,
  public_url text,
  storage_path text,
  duration_ms integer,
  source text,
  is_active boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_q text := NULLIF(btrim(COALESCE(p_query, '')), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT c.id, c.title, c.artist, c.genre, c.public_url, c.storage_path,
         c.duration_ms, c.source, c.is_active, c.created_at
  FROM public.music_catalog AS c
  WHERE v_q IS NULL
     OR (COALESCE(c.title, '') || ' ' || COALESCE(c.artist, '')) ILIKE '%' || v_q || '%'
  ORDER BY c.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_music_list_catalog(text, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_music_list_catalog(text, integer)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_music_update_track(
  p_id uuid,
  p_title text DEFAULT NULL,
  p_artist text DEFAULT NULL,
  p_genre text DEFAULT NULL,
  p_is_active boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  UPDATE public.music_catalog
  SET title     = COALESCE(NULLIF(btrim(COALESCE(p_title, '')), ''), title),
      artist    = COALESCE(NULLIF(btrim(COALESCE(p_artist, '')), ''), artist),
      genre     = CASE WHEN p_genre IS NULL THEN genre
                       ELSE NULLIF(btrim(p_genre), '') END,
      is_active = COALESCE(p_is_active, is_active)
  WHERE id = p_id;
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_music_update_track(uuid, text, text, text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_music_update_track(uuid, text, text, text, boolean)
  TO authenticated;

commit;

NOTIFY pgrst, 'reload schema';
