-- =============================================================================
-- 20260928000002_post_image_aspect_ratio.sql
-- -----------------------------------------------------------------------------
-- Görev 2.8 — Gönderi fotoğraflarının çerçeve oranı.
--
-- Gönderi oluştururken kullanıcı bir çerçeve seçer (Dikey 4:5, Kare 1:1,
-- Yatay 4:3) ve fotoğraflar bu orana kırpılarak yüklenir. Akış kartı ve detay
-- ekranı fotoğrafı bu oranda, kart genişliğinde çizer.
--
-- ## Neden oran veritabanında
--
-- Oran görsel inmeden BİLİNMEZSE kart önce tahmini yükseklikte çizilir, görsel
-- inince boyu değişir ve akış kullanıcının gözü önünde zıplar. Oran satırla
-- birlikte gelince kart ilk karede doğru boyda çizilir.
--
-- NULL = bilinmiyor (eski sürüm istemcilerin, adminin ve botların
-- gönderileri): istemci kare çerçeveye düşer. Mevcut gönderiler
-- 20260928000003'te ölçülerek dolduruldu.
--
-- ## posts'a kolon eklemenin ÜÇ AYAĞI (bkz. 20260920000008)
--
-- 1. ALTER TABLE — tek başına YETMEZ.
-- 2. `posts_with_profiles` view'i yeniden yaratılmalı: `p.*` view
--    OLUŞTURULURKEN genişler, yoksa yeni kolon üye akışında hep null görünür.
-- 3. `public_explore_feed` RPC'si güncellenmeli: misafir akışı AÇIK bir
--    RETURNS TABLE listesi kullanıyor; dönüş tipi değiştiği için DROP + CREATE.
--
-- View ve RPC gövdeleri canlıdaki tanımla (20260920000008) BİREBİR aynı;
-- yalnızca yeni kolon eklendi.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Kolon: genişlik / yükseklik
-- -----------------------------------------------------------------------------
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS image_aspect_ratio real;

ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_image_aspect_ratio_range;
ALTER TABLE public.posts ADD CONSTRAINT posts_image_aspect_ratio_range
  CHECK (image_aspect_ratio IS NULL OR image_aspect_ratio BETWEEN 0.5 AND 2.0);

COMMENT ON COLUMN public.posts.image_aspect_ratio IS
  'Gönderi fotoğraflarının çerçeve oranı (genişlik/yükseklik; 0.8 = 4:5, 1 = 1:1, '
  '1.3333 = 4:3). Akış kartı fotoğrafı bu oranda çizer; NULL = bilinmiyor (kare).';

-- -----------------------------------------------------------------------------
-- 2) posts_with_profiles — `p.*` yeniden genişlesin diye baştan yaratılıyor
--
-- profiles'tan yalnızca GRANT'lı güvenli sütunlar okunur; role ve is_admin
-- kasıtlı NULL (aksi halde security_invoker 42501 fırlatır).
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
  'Posts + profiles LEFT JOIN. security_invoker=true. 2026-09-28: posts.image_aspect_ratio '
  'kolonu eklendiği için view yeniden yaratıldı (p.* oluşturma anında genişler).';

-- -----------------------------------------------------------------------------
-- 3) public_explore_feed — misafir akışına image_aspect_ratio kolonu
--
-- Gövde ve güvenlik sözleşmesi (SECURITY DEFINER, gizli hesap filtreleri,
-- explore_public_access anahtarı, müzik anahtarı) aynen korunuyor.
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
  image_aspect_ratio real,
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
    po.id, po.user_id, po.content, po.images, po.image_aspect_ratio,
    po.background,
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

NOTIFY pgrst, 'reload schema';

COMMIT;
