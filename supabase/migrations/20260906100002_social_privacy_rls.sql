-- ============================================================================
-- SOSYAL GİZLİLİK: RLS SEVİYESİNDE GERÇEK KORUMA
-- ============================================================================
-- Sorun:
--   * "Herkese açık profil" kapatılmış (profile_is_public = false) hesapların
--     gönderileri ve hikayeleri, Keşfet feed'inde ve doğrudan sorgularda
--     HERKESE görünüyordu. Gizlilik yalnızca profil ekranındaki bir if
--     bloğuyla (UI) uygulanıyordu; posts/stories SELECT politikaları
--     "USING (true)" idi.
--   * "Engelle" özelliği hiçbir yerde içerik filtrelemiyordu; engellenen
--     kullanıcının gönderileri feed'de görünmeye devam ediyordu.
--   * follow_requests SELECT politikası "true" olduğu için herkesin takip
--     istekleri (kim kime istek atmış) tüm kullanıcılara okunabiliyordu.
--   * follows INSERT politikası "auth.uid() = follower_id OR auth.uid() =
--     following_id" idi; bu, bir kullanıcının BAŞKA birini kendisini takip
--     ediyor gibi göstermesine izin veriyordu. Takip isteği onayı artık
--     SECURITY DEFINER trigger (handle_follow_request_status_change)
--     üzerinden yapıldığı için bu gevşek kural gereksiz.

begin;

-- ---------------------------------------------------------------------------
-- 1) Yardımcı: karşılıklı engelleme kontrolü
--    blocked_users SELECT politikası yalnızca "kendi engellediklerim"i
--    gösterdiği için, "beni engelleyenler" yönü ancak SECURITY DEFINER bir
--    fonksiyonla kontrol edilebilir.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.social_block_exists(p_other uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.blocked_users b
    WHERE (b.blocker_id = (SELECT auth.uid()) AND b.blocked_id = p_other)
       OR (b.blocker_id = p_other AND b.blocked_id = (SELECT auth.uid()))
  );
$$;

REVOKE ALL ON FUNCTION public.social_block_exists(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.social_block_exists(uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.social_block_exists(uuid) IS
  'İki kullanıcı arasında (her iki yönde) engel var mı? RLS politikalarında kullanılır.';

-- ---------------------------------------------------------------------------
-- 2) Yardımcı: yazarın içeriğini görebilir miyim?
--    Sıra önemli: sahip > admin > engel > herkese açık > takipçi.
-- ---------------------------------------------------------------------------
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
    WHEN public.auth_is_admin() THEN true
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

REVOKE ALL ON FUNCTION public.can_view_social_author(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_view_social_author(uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.can_view_social_author(uuid) IS
  'Gizli hesap + engelleme kurallarını uygular. posts/stories SELECT politikalarında kullanılır.';

-- Politika alt sorgularının indeks kullanması için
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocker_blocked
  ON public.blocked_users(blocker_id, blocked_id);
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked_blocker
  ON public.blocked_users(blocked_id, blocker_id);
CREATE INDEX IF NOT EXISTS idx_follows_follower_following
  ON public.follows(follower_id, following_id);

-- ---------------------------------------------------------------------------
-- 3) posts SELECT
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can view active posts" ON public.posts;
DROP POLICY IF EXISTS posts_select_unified ON public.posts;
DROP POLICY IF EXISTS posts_select_visible ON public.posts;

CREATE POLICY posts_select_visible
ON public.posts
FOR SELECT
USING (
  (
    is_active = true
    OR user_id = (SELECT auth.uid())
    OR public.auth_is_admin()
  )
  AND public.can_view_social_author(user_id)
);

-- ---------------------------------------------------------------------------
-- 4) stories SELECT
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS stories_select_public ON public.stories;
DROP POLICY IF EXISTS stories_select_visible ON public.stories;

CREATE POLICY stories_select_visible
ON public.stories
FOR SELECT
USING (
  (
    expires_at > now()
    OR user_id = (SELECT auth.uid())
    OR public.auth_is_admin()
  )
  AND public.can_view_social_author(user_id)
);

-- ---------------------------------------------------------------------------
-- 5) follow_requests SELECT: yalnızca tarafları görebilir
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Anyone can view follow requests" ON public.follow_requests;
DROP POLICY IF EXISTS follow_requests_select_involved ON public.follow_requests;

CREATE POLICY follow_requests_select_involved
ON public.follow_requests
FOR SELECT
USING (
  follower_id = (SELECT auth.uid())
  OR following_id = (SELECT auth.uid())
  OR public.auth_is_admin()
);

-- ---------------------------------------------------------------------------
-- 6) follows INSERT: yalnızca kendi adına takip edebilirsin
--    (istek onayı SECURITY DEFINER trigger ile follows'a yazıyor)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can follow others" ON public.follows;
DROP POLICY IF EXISTS follows_insert_self ON public.follows;

CREATE POLICY follows_insert_self
ON public.follows
FOR INSERT
WITH CHECK (
  follower_id = (SELECT auth.uid())
  AND following_id IS DISTINCT FROM follower_id
);

-- Kendini takip eden artık kayıt oluşmasın diye mevcut bozuk satırları temizle
DELETE FROM public.follows WHERE follower_id = following_id;

commit;
