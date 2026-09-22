-- =============================================================================
-- 20260920000008_post_story_music.sql
-- -----------------------------------------------------------------------------
-- Gönderiye ve hikayeye müzik iliştirme.
--
-- ## Neden tek bir jsonb kolonu
--
-- Müziğin beş alanı var (adres, başlık, sanatçı, başlangıç anı, süre) ve
-- hiçbirine göre sorgu atmıyoruz — yalnızca gönderiyle birlikte okunup
-- oynatılıyorlar. Beş ayrı kolon açmak `posts` tablosunda beş kat daha fazla
-- bakım demekti: bkz. aşağıdaki view/RPC zorunluluğu.
--
-- ## posts'a kolon eklemenin ÜÇ AYAĞI
--
-- 1. ALTER TABLE — tek başına YETMEZ.
-- 2. `posts_with_profiles` view'i yeniden yaratılmalı. View `p.*` ile tanımlı
--    ama PostgreSQL yıldızı view OLUŞTURULURKEN genişletir; ALTER TABLE sonrası
--    view eski kolon listesini taşımaya devam eder ve yeni kolon Dart tarafında
--    hep null görünür.
-- 3. `public_explore_feed` RPC'si güncellenmeli. Misafir Keşfet akışı bu
--    SECURITY DEFINER fonksiyondan besleniyor ve AÇIK bir RETURNS TABLE listesi
--    kullanıyor; dönüş tipi değiştiği için CREATE OR REPLACE yetmez.
--
-- 2026-09-09'da `posts.background` ile tam olarak bu yaşandı: aynı gönderi üye
-- olarak bakınca renkli, misafir olarak bakınca düzdü.
--
-- ## Anahtarın sunucu tarafı karşılığı
--
-- `music_attach_enabled` kapalıyken tetikleyici YENİ iliştirmeleri sessizce
-- düşürür ve misafir akışı müziği null döndürür. Var olan satırların verisi
-- BİLEREK silinmez — anahtar geri açıldığında gönderilerin müziği geri gelsin
-- diye. Uygulama içinde çalma da aynı anahtara bakar.
-- =============================================================================

begin;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Kolonlar
-- -----------------------------------------------------------------------------
ALTER TABLE public.posts   ADD COLUMN IF NOT EXISTS music jsonb;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS music jsonb;

COMMENT ON COLUMN public.posts.music IS
  'İliştirilmiş müzik: {url, title, artist, start_ms, duration_ms, clipped, catalog_id}. Yoksa NULL.';
COMMENT ON COLUMN public.stories.music IS
  'İliştirilmiş müzik: {url, title, artist, start_ms, duration_ms, clipped, catalog_id}. Yoksa NULL.';

-- -----------------------------------------------------------------------------
-- 2) Yazma kapısı — anahtar kapalıyken iliştirme kabul edilmez
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.music_attach_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NEW.music IS NULL THEN
    RETURN NEW;
  END IF;

  -- Özellik ya da iliştirme kapalıysa müzik sessizce düşer. HATA FIRLATMIYORUZ:
  -- admin anahtarı tam da kullanıcı paylaşıma basarken kapatmış olabilir ve
  -- bu yüzden gönderinin tamamının kaybolması orantısız olurdu.
  IF NOT public.music_flag('music_feature_enabled', true)
     OR NOT public.music_flag('music_attach_enabled', true) THEN
    NEW.music := NULL;
    RETURN NEW;
  END IF;

  -- Adresi olmayan müzik hiçbir işe yaramaz; yarım kayıt tutmayalım.
  IF NULLIF(btrim(COALESCE(NEW.music ->> 'url', '')), '') IS NULL THEN
    NEW.music := NULL;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_posts_music_attach_guard ON public.posts;
CREATE TRIGGER trg_posts_music_attach_guard
  BEFORE INSERT OR UPDATE OF music ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.music_attach_guard();

DROP TRIGGER IF EXISTS trg_stories_music_attach_guard ON public.stories;
CREATE TRIGGER trg_stories_music_attach_guard
  BEFORE INSERT OR UPDATE OF music ON public.stories
  FOR EACH ROW EXECUTE FUNCTION public.music_attach_guard();

-- -----------------------------------------------------------------------------
-- 3) posts_with_profiles — `p.*` yeniden genişlesin diye baştan yaratılıyor
--
-- Tanım 20260909100001 ile BİREBİR aynı: profiles'tan yalnızca GRANT'lı güvenli
-- sütunlar okunur, role ve is_admin kasıtlı NULL (aksi halde security_invoker
-- 42501 fırlatır).
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.posts_with_profiles;

CREATE VIEW public.posts_with_profiles
WITH (security_invoker = true) AS
SELECT
  p.*,
  pr.username,
  pr.full_name,
  pr.avatar_url,
  pr.is_ghost_mode     AS author_is_ghost_mode,
  pr.profile_is_public AS author_profile_public,
  pr.status            AS author_status,
  NULL::BOOLEAN AS author_is_verified,
  NULL::TEXT    AS author_role,
  NULL::BOOLEAN AS author_is_admin,
  (pr.id IS NOT NULL) AS author_profile_exists
FROM posts p
LEFT JOIN profiles pr ON pr.id = p.user_id
WHERE p.is_active = true;

GRANT SELECT ON public.posts_with_profiles TO authenticated, anon;

COMMENT ON VIEW public.posts_with_profiles IS
  'Posts + profiles LEFT JOIN. security_invoker=true. 2026-09-20: posts.music '
  'kolonu eklendiği için view yeniden yaratıldı (p.* oluşturma anında genişler).';

-- -----------------------------------------------------------------------------
-- 4) public_explore_feed — misafir akışına music kolonu
--
-- Gövde ve güvenlik sözleşmesi (SECURITY DEFINER, gizli hesap filtreleri,
-- explore_public_access anahtarı) 20260909100003'teki haliyle korunuyor;
-- yalnızca bir kolon eklendi.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.public_explore_feed(integer, integer);

CREATE FUNCTION public.public_explore_feed(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  content text,
  images text[],
  background text,
  music jsonb,
  location text,
  latitude numeric,
  longitude numeric,
  likes_count integer,
  comments_count integer,
  shares_count integer,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  image_url text,
  is_pinned boolean,
  admin_pinned boolean,
  username text,
  full_name text,
  avatar_url text,
  author_profile_exists boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  -- Anahtar kapalıysa müzik okunmaz. STABLE olduğu için sorgu başına bir kez
  -- değerlendirilir, satır başına değil.
  v_music boolean := public.music_flag('music_feature_enabled', true)
                 AND public.music_flag('music_attach_enabled', true);
BEGIN
  -- Sunucu tarafı kapı: ayar kapalıysa hiçbir şey dönmez.
  IF NOT COALESCE(
       (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
          FROM public.app_settings s WHERE s.key = 'explore_public_access'),
       false
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    po.id, po.user_id, po.content, po.images, po.background,
    CASE WHEN v_music THEN po.music ELSE NULL::jsonb END,
    po.location,
    po.latitude, po.longitude,
    COALESCE(po.likes_count, 0), COALESCE(po.comments_count, 0),
    COALESCE(po.shares_count, 0),
    COALESCE(po.is_active, true), po.created_at, po.updated_at,
    po.image_url, COALESCE(po.is_pinned, false), COALESCE(po.admin_pinned, false),
    pr.username, pr.full_name, pr.avatar_url,
    (pr.id IS NOT NULL)
  FROM public.posts po
  LEFT JOIN public.profiles pr ON pr.id = po.user_id
  WHERE po.is_active = true
    -- Gizli hesapların gönderileri misafire kapalıdır (üye tarafındaki
    -- can_view_social_author() kuralının misafir karşılığı).
    AND COALESCE(pr.profile_is_public, true) = true
    AND COALESCE(pr.is_ghost_mode, false) = false
    AND COALESCE(pr.status, 'active'::public.user_status)
        <> 'deleted'::public.user_status
  ORDER BY COALESCE(po.admin_pinned, false) DESC, po.created_at DESC
  LIMIT v_limit OFFSET v_offset;
END;
$fn$;

REVOKE ALL ON FUNCTION public.public_explore_feed(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_explore_feed(integer, integer)
  TO anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5) Depolar
--
-- İki ayrı kepçe: klipler kısa ömürlü ve küçük, sanatçı başvuruları büyük ve
-- kalıcı. Tek kepçede olsalardı boyut sınırını ikisinden büyüğüne göre açmak
-- ve 15 sn'lik bir klip için 10 MB'lık kapıyı açık bırakmak gerekirdi.
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'post-music', 'post-music', true,
  12582912, -- 12 MB: MP3 klipler ~250 KB, kırpılamayan formatlarda tam dosya
  ARRAY[
    'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/m4a', 'audio/x-m4a',
    'audio/aac', 'audio/ogg', 'audio/wav', 'audio/x-wav', 'audio/flac',
    'audio/webm'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'artist-music', 'artist-music', true,
  10485760, -- 10 MB, music_max_upload_mb ile aynı
  ARRAY[
    'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/m4a', 'audio/x-m4a',
    'audio/aac', 'audio/ogg', 'audio/wav', 'audio/x-wav', 'audio/flac',
    'audio/webm'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Herkes dinleyebilir (misafir Keşfet akışı da gönderideki müziği çalar).
DROP POLICY IF EXISTS "post_music_public_read" ON storage.objects;
CREATE POLICY "post_music_public_read" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'post-music');

DROP POLICY IF EXISTS "artist_music_public_read" ON storage.objects;
CREATE POLICY "artist_music_public_read" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'artist-music');

-- Yazma: herkes YALNIZCA kendi klasörüne. Yol biçimi `<user_id>/<dosya>`.
DROP POLICY IF EXISTS "post_music_own_insert" ON storage.objects;
CREATE POLICY "post_music_own_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'post-music'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "post_music_own_delete" ON storage.objects;
CREATE POLICY "post_music_own_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'post-music'
    AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin())
  );

DROP POLICY IF EXISTS "artist_music_own_insert" ON storage.objects;
CREATE POLICY "artist_music_own_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'artist-music'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "artist_music_own_delete" ON storage.objects;
CREATE POLICY "artist_music_own_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'artist-music'
    AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin())
  );

commit;

NOTIFY pgrst, 'reload schema';
