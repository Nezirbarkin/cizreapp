-- =============================================================================
-- 20260909100003_public_explore_feed_background.sql
-- -----------------------------------------------------------------------------
-- AMAÇ: Misafir Keşfet akışında da arka planlı metin gönderileri doğru çizilsin.
--
-- public_explore_feed, üye akışındaki `posts_with_profiles` view'ının aksine
-- AÇIK bir RETURNS TABLE listesi kullanıyor. 20260909100001 ile eklenen
-- posts.background bu listede olmadığı için misafir tarafında her metin
-- gönderisi "arka planı yokmuş gibi" (sade) görünüyordu — aynı gönderi üye
-- olarak bakınca renkli, misafir olarak bakınca düz.
--
-- Fonksiyonun gövdesi ve güvenlik sözleşmesi (SECURITY DEFINER, gizli hesap
-- filtreleri, explore_public_access anahtarı) 20260908130003'teki haliyle
-- BİREBİR korunuyor; yalnızca bir kolon eklendi. Dönüş tipi değiştiği için
-- CREATE OR REPLACE yetmez, DROP + CREATE gerekiyor.
-- =============================================================================

begin;

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
AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
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
    po.id, po.user_id, po.content, po.images, po.background, po.location,
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
$$;

REVOKE ALL ON FUNCTION public.public_explore_feed(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_explore_feed(integer, integer)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

commit;
