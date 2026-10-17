-- =============================================================================
-- Canlı yayın: tekrar izleme (yayın kaydı)
-- =============================================================================
--
-- Yayın bitince izleyici siyah "Yayın sona erdi" ekranı yerine yayının kaydını
-- izler. Kayıt yayıncının telefonunda Agora yerel kaydedicisiyle alınır
-- (3 dakikalık MP4 parçalar) ve özel 'live-replays' kovasına yüklenir:
--
--   live-replays/<session_id>/part-0001.mp4, part-0002.mp4, …
--
-- Neden bulut kaydı değil: Agora Cloud Recording'in "S3 uyumlu depo" seçeneği
-- yalnız alan adı kabul ediyor (Supabase'in S3 adresi /storage/v1/s3 yolunu
-- ister); ayrıca ayrı REST anahtarı ve dakika ücreti gerektiriyordu. Parça
-- ≤ 50 MB (tek dosya sınırı) kalsın diye kayıt 3 dakikada bir bölünür.
--
-- Akış (tüm yazmalar DEFINER RPC; tablo istemciye kapalı):
--   live_replay_begin(session)            yayın canlıyken; yönetim kaydı kapattıysa enabled=false
--   [Storage upload]                      INSERT politikası: yalnız yayıncı, durum 'recording'
--   live_replay_add_part(session, n, ms)  nesne depoda mı bakılır, toplamlar güncellenir
--   live_replay_finish(session)           yayın bittikten ve parçalar yüklendikten sonra
--   live_replay_parts(session)            izleyici: parça listesi (görünürlük kuralıyla)
--   live_replay_delete(session)           yayıncı ya da yönetici; dönen yolları istemci siler
--   live_replay_cleanup_batch(limit)      yalnız service_role: süre dolumu + silinecek
--                                         nesneler (live-replay-cleanup, saatlik cron)
--
-- Görünürlük canlı yayınla aynı (private.live_session_listable): mağaza yayını
-- mağaza aktif/onaylıysa herkese; kullanıcı yayınında gizli hesap yalnız
-- takipçiye, engelleşen hiç. Yayıncı ve yönetim her zaman görür. Kayıt yönetici
-- ayarındaki gün kadar saklanır (live_replay_days, varsayılan 30). Yönetici
-- "yeni yayınları kaydet" anahtarını (live_replay_enabled) kapatırsa var olan
-- kayıtlar süreleri dolana kadar kalır.
--
-- private.live_session_json'a 'replay' anahtarı eklenir; böylece akış, geçmiş,
-- ayrıntı, Yayınlarım, ana sayfa kartı ve admin listesi kaydı kendiliğinden
-- taşır. Gövdenin geri kalanı 20261004000001'deki tanımla birebir aynıdır.
--
-- Canlı test: supabase/tests/manual/live_replays_test.sql (kendini geri alır).

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Kova: özel, yalnız MP4, parça başına 50 MB
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('live-replays', 'live-replays', false, 52428800, ARRAY['video/mp4'])
ON CONFLICT (id) DO UPDATE
  SET public = false,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- -----------------------------------------------------------------------------
-- 2) Şema
-- -----------------------------------------------------------------------------
ALTER TABLE public.live_sessions
  ADD COLUMN IF NOT EXISTS replay_state text,
  ADD COLUMN IF NOT EXISTS replay_parts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS replay_duration_ms bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS replay_size_bytes bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS replay_finished_at timestamptz,
  ADD COLUMN IF NOT EXISTS replay_deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS replay_deleted_reason text;

ALTER TABLE public.live_sessions DROP CONSTRAINT IF EXISTS live_sessions_replay_state_check;
ALTER TABLE public.live_sessions ADD CONSTRAINT live_sessions_replay_state_check
  CHECK (replay_state IS NULL OR replay_state IN ('recording', 'ready', 'failed', 'deleted'));
ALTER TABLE public.live_sessions DROP CONSTRAINT IF EXISTS live_sessions_replay_deleted_reason_check;
ALTER TABLE public.live_sessions ADD CONSTRAINT live_sessions_replay_deleted_reason_check
  CHECK (replay_deleted_reason IS NULL OR replay_deleted_reason IN ('host', 'admin', 'expired'));

COMMENT ON COLUMN public.live_sessions.replay_state IS
  'Tekrar izleme kaydı: NULL = kayıt yok, recording = parçalar geliyor, ready = yayıncı yüklemeyi bitirdi, '
  'failed = hiç parça gelmedi, deleted = yayıncı/yönetici sildi ya da süresi doldu.';

CREATE INDEX IF NOT EXISTS live_sessions_replay_open_idx
  ON public.live_sessions (ended_at)
  WHERE replay_state IN ('recording', 'ready', 'failed');

CREATE TABLE IF NOT EXISTS public.live_replay_parts (
  session_id uuid NOT NULL REFERENCES public.live_sessions(id) ON DELETE CASCADE,
  part_no integer NOT NULL CHECK (part_no BETWEEN 1 AND 999),
  object_path text NOT NULL,
  duration_ms integer NOT NULL CHECK (duration_ms BETWEEN 1 AND 3600000),
  size_bytes bigint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, part_no)
);

ALTER TABLE public.live_replay_parts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.live_replay_parts FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.live_replay_parts IS
  'Canlı yayın kaydının yüklenmiş parçaları. İstemciye kapalı; yalnız live_replay_* RPC''leri okur/yazar.';

-- -----------------------------------------------------------------------------
-- 3) Yardımcılar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.live_replay_days()
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT private.live_setting_int('live_replay_days', 30, 1, 365);
$fn$;

CREATE OR REPLACE FUNCTION private.live_replay_part_path(p_session_id uuid, p_part_no integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT p_session_id::text || '/part-' || lpad(p_part_no::text, 4, '0') || '.mp4';
$fn$;

-- '<uuid>/part-0001.mp4' → yayın kimliği; biçim dışı yol → NULL.
CREATE OR REPLACE FUNCTION private.live_replay_path_session(p_name text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/part-[0-9]{4}\.mp4$'
      THEN split_part(p_name, '/', 1)::uuid
  END;
$fn$;

CREATE OR REPLACE FUNCTION private.live_replay_path_part(p_name text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN private.live_replay_path_session(p_name) IS NOT NULL
      THEN substring(p_name FROM '/part-([0-9]{4})\.mp4$')::integer
  END;
$fn$;

-- Kaydı kim izleyebilir: yayıncı ve yönetim her zaman; izleyici yayın bittikten
-- sonra, saklama süresi içinde ve canlı yayının görünürlük kuralıyla.
CREATE OR REPLACE FUNCTION private.live_replay_visible(p_session_id uuid, p_viewer uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v record;
BEGIN
  SELECT ls.shop_id, ls.host_user_id, ls.status, ls.ended_at, ls.replay_state
    INTO v
    FROM public.live_sessions ls
   WHERE ls.id = p_session_id;
  IF NOT FOUND OR v.replay_state IS NULL OR v.replay_state = 'deleted' THEN
    RETURN false;
  END IF;
  IF p_viewer IS NOT NULL AND (p_viewer = v.host_user_id OR private.live_is_staff(p_viewer)) THEN
    RETURN true;
  END IF;
  IF v.status <> 'ended' OR v.ended_at IS NULL
     OR v.ended_at <= now() - make_interval(days => private.live_replay_days()) THEN
    RETURN false;
  END IF;
  RETURN private.live_session_listable(v.shop_id, v.host_user_id, p_viewer);
END;
$fn$;

-- İstemcinin gördüğü kayıt özeti. state: recording (yayın sürüyor) |
-- processing (yayın bitti, parçalar hâlâ yükleniyor) | ready | failed |
-- deleted | expired. Kayıt hiç başlamadıysa NULL.
CREATE OR REPLACE FUNCTION private.live_replay_json(ls public.live_sessions)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_expires timestamptz;
  v_state text;
  v_gone boolean;
BEGIN
  IF ls.replay_state IS NULL THEN
    RETURN NULL;
  END IF;
  v_expires := CASE
    WHEN ls.ended_at IS NULL OR ls.replay_state = 'deleted' THEN NULL
    ELSE ls.ended_at + make_interval(days => private.live_replay_days())
  END;
  v_state := CASE
    WHEN ls.replay_state = 'deleted' THEN 'deleted'
    WHEN v_expires IS NOT NULL AND v_expires <= now() THEN 'expired'
    WHEN ls.replay_state = 'recording' AND ls.status = 'ended' THEN 'processing'
    ELSE ls.replay_state
  END;
  v_gone := v_state IN ('deleted', 'expired');
  RETURN jsonb_build_object(
    'state', v_state,
    'parts', CASE WHEN v_gone THEN 0 ELSE ls.replay_parts END,
    'duration_ms', CASE WHEN v_gone THEN 0 ELSE ls.replay_duration_ms END,
    'size_bytes', CASE WHEN v_gone THEN 0 ELSE ls.replay_size_bytes END,
    'expires_at', CASE WHEN v_gone THEN NULL ELSE v_expires END,
    'deleted_reason', ls.replay_deleted_reason
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 4) Depolama politikaları (çağıranın rolüyle çalışır → DEFINER sarmalayıcılar)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_replay_object_visible(p_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_id uuid := private.live_replay_path_session(p_name);
BEGIN
  RETURN v_id IS NOT NULL AND private.live_replay_visible(v_id, auth.uid());
END;
$fn$;

-- Yükleme yalnız yayıncıya, kayıt açıkken ('recording') ve yayın bittikten
-- sonra en çok 7 gün (telefon çevrimdışı kalıp sonra yükleyebilsin).
CREATE OR REPLACE FUNCTION public.live_replay_upload_allowed(p_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_id uuid := private.live_replay_path_session(p_name);
  v_part integer := private.live_replay_path_part(p_name);
  v_uid uuid := auth.uid();
BEGIN
  IF v_id IS NULL OR v_uid IS NULL OR v_part IS NULL OR v_part < 1 OR v_part > 999 THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1
      FROM public.live_sessions ls
     WHERE ls.id = v_id
       AND ls.host_user_id = v_uid
       AND ls.replay_state = 'recording'
       AND (ls.status = 'live' OR (ls.status = 'ended' AND ls.ended_at > now() - interval '7 days'))
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_replay_delete_allowed(p_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_id uuid := private.live_replay_path_session(p_name);
  v_uid uuid := auth.uid();
BEGIN
  IF v_id IS NULL OR v_uid IS NULL THEN
    RETURN false;
  END IF;
  RETURN public.auth_is_admin()
      OR EXISTS (SELECT 1 FROM public.live_sessions ls WHERE ls.id = v_id AND ls.host_user_id = v_uid);
END;
$fn$;

DROP POLICY IF EXISTS live_replays_select ON storage.objects;
CREATE POLICY live_replays_select ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'live-replays' AND public.live_replay_object_visible(name));

DROP POLICY IF EXISTS live_replays_insert ON storage.objects;
CREATE POLICY live_replays_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'live-replays' AND public.live_replay_upload_allowed(name));

-- Yarıda kalan yüklemenin yeniden denenmesi (upsert) için.
DROP POLICY IF EXISTS live_replays_update ON storage.objects;
CREATE POLICY live_replays_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'live-replays' AND public.live_replay_upload_allowed(name))
  WITH CHECK (bucket_id = 'live-replays' AND public.live_replay_upload_allowed(name));

DROP POLICY IF EXISTS live_replays_delete ON storage.objects;
CREATE POLICY live_replays_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'live-replays' AND public.live_replay_delete_allowed(name));

-- -----------------------------------------------------------------------------
-- 5) Yayın JSON'u: 20261004000001 tanımı + 'replay'
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.live_session_json(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_json jsonb;
BEGIN
  SELECT jsonb_build_object(
    'id', ls.id,
    'kind', CASE WHEN ls.shop_id IS NULL THEN 'user' ELSE 'shop' END,
    'shop_id', ls.shop_id,
    'host_user_id', ls.host_user_id,
    'title', ls.title,
    'description', ls.description,
    'cover_image_url', ls.cover_image_url,
    'channel_name', ls.channel_name,
    'status', ls.status,
    'is_live', (ls.status = 'live' AND ls.last_heartbeat_at > now() - interval '2 minutes'),
    'started_at', ls.started_at,
    'ended_at', ls.ended_at,
    'ended_reason', ls.ended_reason,
    'viewer_count', ls.viewer_count,
    'peak_viewer_count', ls.peak_viewer_count,
    'last_heartbeat_at', ls.last_heartbeat_at,
    'created_at', ls.created_at,
    'updated_at', ls.updated_at,
    'shop_name', s.name,
    'shop_logo_url', s.logo_url,
    -- Yayıncı kimliği yalnız kullanıcı yayınında (satıcının kişisel hesabı
    -- mağaza yayınında gösterilmez). Önce kullanıcı adı, yoksa ad.
    'host_display_name', CASE WHEN ls.shop_id IS NULL THEN
      COALESCE(NULLIF(btrim(h.username), ''), NULLIF(btrim(h.full_name), ''), 'Kullanıcı') END,
    'host_username', CASE WHEN ls.shop_id IS NULL THEN NULLIF(btrim(h.username), '') END,
    'host_avatar_url', CASE WHEN ls.shop_id IS NULL THEN h.avatar_url END,
    'replay', private.live_replay_json(ls),
    'pinned_product', CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'image_url', p.image_url,
      'price', p.price,
      'discount_price', p.discount_price,
      'effective_price', CASE
        WHEN p.discount_price IS NOT NULL AND p.discount_price > 0 AND p.discount_price < p.price
          THEN p.discount_price
        ELSE p.price
      END,
      'is_available', COALESCE(p.is_available, false)
    ) END
  )
  INTO v_json
  FROM public.live_sessions ls
  LEFT JOIN public.shops s ON s.id = ls.shop_id
  LEFT JOIN public.profiles h ON h.id = ls.host_user_id
  LEFT JOIN public.products p ON p.id = ls.pinned_product_id
  WHERE ls.id = p_session_id;

  RETURN v_json;
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 6) Yayıncı RPC'leri
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_replay_begin(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_next integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v.host_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;
  IF v.status <> 'live' THEN
    RAISE EXCEPTION 'Yayın şu an canlı değil' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_LIVE';
  END IF;

  IF v.replay_state IS NULL THEN
    -- Yönetim yeni yayınların kaydını kapattıysa kayıt hiç başlamaz.
    IF NOT private.live_setting_bool('live_replay_enabled', true) THEN
      RETURN jsonb_build_object('enabled', false, 'reason', 'disabled');
    END IF;
    UPDATE public.live_sessions SET replay_state = 'recording' WHERE id = p_session_id;
  ELSIF v.replay_state <> 'recording' THEN
    RETURN jsonb_build_object('enabled', false, 'reason', v.replay_state);
  END IF;

  -- Sürdürülen yayında (uygulama kapanıp açıldı) numaralar kaldığı yerden.
  SELECT COALESCE(max(part_no), 0) + 1 INTO v_next
    FROM public.live_replay_parts
   WHERE session_id = p_session_id;

  RETURN jsonb_build_object(
    'enabled', true,
    'next_part', v_next,
    'part_seconds', private.live_setting_int('live_replay_part_seconds', 180, 60, 600),
    'max_parts', 999,
    'days', private.live_replay_days()
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_replay_add_part(p_session_id uuid, p_part_no integer, p_duration_ms integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_path text;
  v_size bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v.host_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;
  IF v.replay_state IS DISTINCT FROM 'recording' THEN
    RAISE EXCEPTION 'Bu yayının kaydı kapalı' USING ERRCODE = 'P0001', HINT = 'LIVE_REPLAY_CLOSED';
  END IF;
  IF p_part_no IS NULL OR p_part_no < 1 OR p_part_no > 999
     OR p_duration_ms IS NULL OR p_duration_ms < 1 OR p_duration_ms > 3600000 THEN
    RAISE EXCEPTION 'Geçersiz kayıt parçası' USING ERRCODE = 'P0001', HINT = 'LIVE_REPLAY_PART_INVALID';
  END IF;

  v_path := private.live_replay_part_path(p_session_id, p_part_no);
  SELECT COALESCE((o.metadata ->> 'size')::bigint, 0) INTO v_size
    FROM storage.objects o
   WHERE o.bucket_id = 'live-replays' AND o.name = v_path;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kayıt parçası depoda yok' USING ERRCODE = 'P0001', HINT = 'LIVE_REPLAY_PART_MISSING';
  END IF;

  INSERT INTO public.live_replay_parts (session_id, part_no, object_path, duration_ms, size_bytes)
  VALUES (p_session_id, p_part_no, v_path, p_duration_ms, v_size)
  ON CONFLICT (session_id, part_no) DO UPDATE
    SET duration_ms = EXCLUDED.duration_ms,
        size_bytes = EXCLUDED.size_bytes,
        created_at = now();

  UPDATE public.live_sessions ls
     SET replay_parts = a.n,
         replay_duration_ms = a.ms,
         replay_size_bytes = a.bytes
    FROM (SELECT count(*)::integer AS n,
                 COALESCE(sum(rp.duration_ms), 0)::bigint AS ms,
                 COALESCE(sum(rp.size_bytes), 0)::bigint AS bytes
            FROM public.live_replay_parts rp
           WHERE rp.session_id = p_session_id) a
   WHERE ls.id = p_session_id
  RETURNING ls.* INTO v;

  RETURN private.live_replay_json(v);
END;
$fn$;

-- Yayın bitip tüm parçalar yüklenince: parça varsa 'ready', yoksa 'failed'.
-- Yayın sürüyorsa bir şey değişmez (istemci bitişten sonra yeniden çağırır).
CREATE OR REPLACE FUNCTION public.live_replay_finish(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v.host_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;
  IF v.replay_state = 'recording' AND v.status = 'ended' THEN
    UPDATE public.live_sessions
       SET replay_state = CASE WHEN v.replay_parts > 0 THEN 'ready' ELSE 'failed' END,
           replay_finished_at = now()
     WHERE id = p_session_id
    RETURNING * INTO v;
  END IF;
  RETURN private.live_replay_json(v);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 7) İzleyici: parça listesi (yollar; imzalı adresi istemci Storage'dan alır,
--    SELECT politikası aynı görünürlük kuralını uygular)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_replay_parts(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
BEGIN
  IF NOT private.live_replay_visible(p_session_id, auth.uid()) THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id;
  RETURN private.live_replay_json(v) || jsonb_build_object(
    'session_id', p_session_id,
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'part_no', rp.part_no,
               'path', rp.object_path,
               'duration_ms', rp.duration_ms
             ) ORDER BY rp.part_no)
        FROM public.live_replay_parts rp
       WHERE rp.session_id = p_session_id
    ), '[]'::jsonb)
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 8) Silme: yayıncı ya da yönetici. Kayıt hemen 'deleted' olur (izlenemez);
--    dönen yolları istemci Storage API'siyle siler (SQL'den silinemez:
--    storage.protect_objects_delete). Silinemeyen artıkları temizlik toplar.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_replay_delete(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_uid uuid := auth.uid();
  v_paths jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v.host_user_id <> v_uid AND NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;
  IF v.status <> 'ended' THEN
    RAISE EXCEPTION 'Yayın sürerken kayıt silinemez' USING ERRCODE = 'P0001', HINT = 'LIVE_REPLAY_NOT_ENDED';
  END IF;

  SELECT COALESCE(jsonb_agg(o.name ORDER BY o.name), '[]'::jsonb) INTO v_paths
    FROM storage.objects o
   WHERE o.bucket_id = 'live-replays'
     AND o.name LIKE p_session_id::text || '/%';

  IF v.replay_state IS NOT NULL AND v.replay_state <> 'deleted' THEN
    DELETE FROM public.live_replay_parts WHERE session_id = p_session_id;
    UPDATE public.live_sessions
       SET replay_state = 'deleted',
           replay_parts = 0,
           replay_duration_ms = 0,
           replay_size_bytes = 0,
           replay_deleted_at = now(),
           replay_deleted_reason = CASE WHEN v.host_user_id = v_uid THEN 'host' ELSE 'admin' END
     WHERE id = p_session_id
    RETURNING * INTO v;
  END IF;

  RETURN jsonb_build_object('replay', private.live_replay_json(v), 'paths', v_paths);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 9) Temizlik (yalnız service_role; live-replay-cleanup Edge Function çağırır)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_replay_cleanup_batch(p_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 200), 1), 1000);
  v_days integer := private.live_replay_days();
  v_expired integer;
  v_finalized integer;
  v_paths jsonb;
BEGIN
  -- Saklama süresi dolan kayıtlar silinmiş sayılır (izlenemez olur).
  WITH gone AS (
    UPDATE public.live_sessions
       SET replay_state = 'deleted',
           replay_parts = 0,
           replay_duration_ms = 0,
           replay_size_bytes = 0,
           replay_deleted_at = now(),
           replay_deleted_reason = 'expired'
     WHERE replay_state IN ('recording', 'ready', 'failed')
       AND status = 'ended'
       AND ended_at <= now() - make_interval(days => v_days)
    RETURNING id
  ), dropped AS (
    DELETE FROM public.live_replay_parts rp USING gone g WHERE rp.session_id = g.id RETURNING 1
  )
  SELECT count(*) INTO v_expired FROM gone;

  -- Yükleme penceresi (bitişten 7 gün) kapanan kayıt sonlanır.
  WITH done AS (
    UPDATE public.live_sessions
       SET replay_state = CASE WHEN replay_parts > 0 THEN 'ready' ELSE 'failed' END,
           replay_finished_at = now()
     WHERE replay_state = 'recording'
       AND status = 'ended'
       AND ended_at <= now() - interval '7 days'
    RETURNING 1
  )
  SELECT count(*) INTO v_finalized FROM done;

  -- Silinecek nesneler: silinmiş kaydın dosyaları, sahipsiz/biçim dışı
  -- dosyalar ve kaydı kapanmış yayının parçalara işlenmemiş artıkları.
  SELECT COALESCE(jsonb_agg(x.name ORDER BY x.created_at), '[]'::jsonb) INTO v_paths
    FROM (
      SELECT o.name, o.created_at
        FROM storage.objects o
        LEFT JOIN public.live_sessions ls ON ls.id = private.live_replay_path_session(o.name)
       WHERE o.bucket_id = 'live-replays'
         AND (
           (ls.id IS NULL AND o.created_at < now() - interval '1 day')
           OR ls.replay_state = 'deleted'
           OR (ls.replay_state IN ('ready', 'failed')
               AND o.created_at < now() - interval '1 day'
               AND NOT EXISTS (SELECT 1 FROM public.live_replay_parts rp
                                WHERE rp.session_id = ls.id AND rp.object_path = o.name))
         )
       ORDER BY o.created_at
       LIMIT v_limit
    ) x;

  RETURN jsonb_build_object('expired', v_expired, 'finalized', v_finalized, 'paths', v_paths, 'days', v_days);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 10) Yönetici ayarları: 20260928000021 tanımları + kayıt anahtarları
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_live_options()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'notify_enabled', private.live_setting_bool('live_notify_enabled', true),
    'notify_cooldown_hours', private.live_setting_int('live_notify_cooldown_hours', 3, 0, 72),
    'notify_followers', private.live_setting_bool('live_notify_followers', true),
    'notify_product_fans', private.live_setting_bool('live_notify_product_fans', true),
    'notify_customers', private.live_setting_bool('live_notify_customers', false),
    'notify_max_recipients', private.live_setting_int('live_notify_max_recipients', 2000, 0, 20000),
    'home_card_enabled', private.live_setting_bool('live_home_card_enabled', true),
    'history_days', private.live_history_days(),
    'replay_enabled', private.live_setting_bool('live_replay_enabled', true),
    'replay_days', private.live_replay_days(),
    'stats', jsonb_build_object(
      'subscriptions', (SELECT count(*) FROM public.live_subscriptions),
      'subscribed_shops', (SELECT count(DISTINCT shop_id) FROM public.live_subscriptions),
      'notifications_30d', (SELECT count(*) FROM public.live_notify_log
                             WHERE skipped IS NULL AND notified_at > now() - interval '30 days'),
      'recipients_30d', (SELECT COALESCE(sum(recipients), 0) FROM public.live_notify_log
                          WHERE skipped IS NULL AND notified_at > now() - interval '30 days'),
      'cooldown_skips_30d', (SELECT count(*) FROM public.live_notify_log
                              WHERE skipped = 'cooldown' AND notified_at > now() - interval '30 days'),
      'replays', (SELECT count(*) FROM public.live_sessions
                   WHERE replay_state IN ('recording', 'ready') AND replay_parts > 0),
      'replay_size_bytes', (SELECT COALESCE(sum(replay_size_bytes), 0) FROM public.live_sessions
                             WHERE replay_state IN ('recording', 'ready', 'failed'))
    )
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_set_live_options(p_options jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_key text;
  v_value jsonb;
  v_setting text;
  v_text text;
  v_num numeric;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_options IS NULL OR jsonb_typeof(p_options) <> 'object' THEN
    RAISE EXCEPTION 'Geçersiz ayar' USING ERRCODE = 'P0001', HINT = 'LIVE_OPTIONS_INVALID';
  END IF;

  FOR v_key, v_value IN SELECT e.key, e.value FROM jsonb_each(p_options) e LOOP
    v_setting := CASE v_key
      WHEN 'notify_enabled' THEN 'live_notify_enabled'
      WHEN 'notify_cooldown_hours' THEN 'live_notify_cooldown_hours'
      WHEN 'notify_followers' THEN 'live_notify_followers'
      WHEN 'notify_product_fans' THEN 'live_notify_product_fans'
      WHEN 'notify_customers' THEN 'live_notify_customers'
      WHEN 'notify_max_recipients' THEN 'live_notify_max_recipients'
      WHEN 'home_card_enabled' THEN 'live_home_card_enabled'
      WHEN 'history_days' THEN 'live_history_days'
      WHEN 'replay_enabled' THEN 'live_replay_enabled'
      WHEN 'replay_days' THEN 'live_replay_days'
    END;
    IF v_setting IS NULL THEN
      RAISE EXCEPTION 'Bilinmeyen ayar: %', v_key USING ERRCODE = 'P0001', HINT = 'LIVE_OPTIONS_INVALID';
    END IF;

    IF v_key IN ('notify_enabled', 'notify_followers', 'notify_product_fans', 'notify_customers',
                 'home_card_enabled', 'replay_enabled') THEN
      IF jsonb_typeof(v_value) <> 'boolean' THEN
        RAISE EXCEPTION 'Geçersiz değer: %', v_key USING ERRCODE = 'P0001', HINT = 'LIVE_OPTIONS_INVALID';
      END IF;
      v_text := CASE WHEN (v_value #>> '{}')::boolean THEN 'true' ELSE 'false' END;
    ELSE
      IF jsonb_typeof(v_value) <> 'number' THEN
        RAISE EXCEPTION 'Geçersiz değer: %', v_key USING ERRCODE = 'P0001', HINT = 'LIVE_OPTIONS_INVALID';
      END IF;
      v_num := (v_value #>> '{}')::numeric;
      v_text := round(CASE v_key
        WHEN 'notify_cooldown_hours' THEN LEAST(GREATEST(v_num, 0), 72)
        WHEN 'notify_max_recipients' THEN LEAST(GREATEST(v_num, 0), 20000)
        WHEN 'replay_days' THEN LEAST(GREATEST(v_num, 1), 365)
        ELSE LEAST(GREATEST(v_num, 1), 180)
      END)::integer::text;
    END IF;

    INSERT INTO public.app_settings (key, value, updated_at)
    VALUES (v_setting, to_jsonb(v_text), now())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at;
  END LOOP;

  RETURN public.admin_live_options();
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 11) Yetkiler
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION private.live_replay_days() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.live_replay_part_path(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.live_replay_path_session(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.live_replay_path_part(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.live_replay_visible(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.live_replay_json(public.live_sessions) FROM PUBLIC, anon, authenticated;

-- Politikalar çağıranın rolüyle değerlendirilir.
REVOKE ALL ON FUNCTION public.live_replay_object_visible(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_replay_object_visible(text) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.live_replay_upload_allowed(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_replay_upload_allowed(text) TO authenticated;
REVOKE ALL ON FUNCTION public.live_replay_delete_allowed(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_replay_delete_allowed(text) TO authenticated;

REVOKE ALL ON FUNCTION public.live_replay_begin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_replay_begin(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.live_replay_add_part(uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_replay_add_part(uuid, integer, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.live_replay_finish(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_replay_finish(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.live_replay_delete(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_replay_delete(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.live_replay_parts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_replay_parts(uuid) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.live_replay_cleanup_batch(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.live_replay_cleanup_batch(integer) TO service_role;

REVOKE ALL ON FUNCTION public.admin_live_options() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_live_options() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_set_live_options(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_live_options(jsonb) TO authenticated;

-- -----------------------------------------------------------------------------
-- 12) Saatlik temizlik: live-replay-cleanup Edge Function (kimlik bilgileri
--     vault'ta; komut smm-order-status-check cron'unun komutundan üretilir).
-- -----------------------------------------------------------------------------
DO $cron$
DECLARE
  v_cmd text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RETURN;
  END IF;
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'smm-order-status-check-5min';
  IF v_cmd IS NULL THEN
    RAISE NOTICE 'smm-order-status-check-5min bulunamadı; live-replay-cleanup cron''u kurulmadı';
    RETURN;
  END IF;

  PERFORM cron.unschedule('live-replay-cleanup-hourly')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'live-replay-cleanup-hourly');
  PERFORM cron.schedule(
    'live-replay-cleanup-hourly',
    '23 * * * *',
    replace(v_cmd, 'smm-order-status-check', 'live-replay-cleanup')
  );
END;
$cron$;

COMMIT;

NOTIFY pgrst, 'reload schema';
