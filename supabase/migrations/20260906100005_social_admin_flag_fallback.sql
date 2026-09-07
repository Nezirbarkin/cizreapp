-- ============================================================================
-- GİZLİLİK POLİTİKALARINDA is_admin BAYRAĞINI DA KABUL ET
-- ============================================================================
-- 20260906100002 migration'ı admin kontrolü için mevcut auth_is_admin()
-- yardımcısını kullanıyor; o da yalnızca profiles.role = 'admin' bakıyor.
-- Ancak eski posts/stories politikaları "role = 'admin' OR is_admin = true"
-- şeklindeydi. Bugün iki alan da tutarlı (uyumsuz satır yok) ama ileride
-- yalnızca is_admin bayrağı işaretlenen bir yönetici, admin panelinde gizli
-- hesapların gönderilerini göremezdi. Kontrolü ikisini de kapsayacak şekilde
-- genişletiyoruz.

begin;

CREATE OR REPLACE FUNCTION public.social_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND (p.role = 'admin' OR p.is_admin = true)
  );
$$;

REVOKE ALL ON FUNCTION public.social_is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.social_is_admin() TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_view_social_author(p_author uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    -- Yazarı silinmiş (orphan) içerik herkese açık kalır
    WHEN p_author IS NULL THEN true
    WHEN p_author = (SELECT auth.uid()) THEN true
    WHEN public.social_is_admin() THEN true
    WHEN public.social_block_exists(p_author) THEN false
    WHEN COALESCE(
           (SELECT pr.profile_is_public FROM public.profiles pr WHERE pr.id = p_author),
           true
         ) THEN true
    ELSE EXISTS (
      SELECT 1 FROM public.follows f
      WHERE f.follower_id = (SELECT auth.uid())
        AND f.following_id = p_author
    )
  END;
$$;

-- posts / stories politikalarındaki doğrudan auth_is_admin() çağrılarını da
-- güncelle (pasif gönderi ve süresi dolmuş hikaye görünürlüğü için).
DROP POLICY IF EXISTS posts_select_visible ON public.posts;
CREATE POLICY posts_select_visible
ON public.posts
FOR SELECT
USING (
  (
    is_active = true
    OR user_id = (SELECT auth.uid())
    OR public.social_is_admin()
  )
  AND public.can_view_social_author(user_id)
);

DROP POLICY IF EXISTS stories_select_visible ON public.stories;
CREATE POLICY stories_select_visible
ON public.stories
FOR SELECT
USING (
  (
    expires_at > now()
    OR user_id = (SELECT auth.uid())
    OR public.social_is_admin()
  )
  AND public.can_view_social_author(user_id)
);

DROP POLICY IF EXISTS follow_requests_select_involved ON public.follow_requests;
CREATE POLICY follow_requests_select_involved
ON public.follow_requests
FOR SELECT
USING (
  follower_id = (SELECT auth.uid())
  OR following_id = (SELECT auth.uid())
  OR public.social_is_admin()
);

DROP POLICY IF EXISTS post_comments_delete_allowed ON public.post_comments;
CREATE POLICY post_comments_delete_allowed
ON public.post_comments
FOR DELETE
USING (
  user_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1 FROM public.posts p
    WHERE p.id = post_comments.post_id
      AND p.user_id = (SELECT auth.uid())
  )
  OR public.social_is_admin()
);

commit;
