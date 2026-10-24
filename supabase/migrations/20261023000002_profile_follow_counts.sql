-- ============================================================================
-- Profil sayaçları tek RPC'de (2026-10-23)
-- ----------------------------------------------------------------------------
-- Profil ekranları takipçi/takip/arkadaş sayısını bulmak için o kişinin TÜM
-- takip satırlarını (iki ayrı sorguyla, art arda) indirip telefonda sayıyordu.
-- PostgREST'in 1000 satır tavanı yüzünden popüler hesapta sayılar 1000'de
-- takılıyordu; gönderi sayısı da yüklenen gönderi listesinin uzunluğuydu
-- (gizli hesapta takip etmeyene 0, sayfalı yüklemede yanlış).
--
-- get_follow_counts(p_user_id) → {followers, following, friends, posts}
--   * followers / following / friends: follows tablosu zaten herkese okunur
--     (follows_select_policy USING true) — yeni bir bilgi açılmıyor.
--   * posts: etkin gönderi SAYISI. Gizli hesapta da sayı görünür (içerik
--     değil); Instagram davranışı. İçeriğin kendisi RLS'te kalır.
--   * Hayalet/silinmiş hesap için sayılar yine döner; profil ekranı zaten
--     o hesabı göstermiyor.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_follow_counts(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_followers integer;
  v_following integer;
  v_friends integer;
  v_posts integer;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('followers', 0, 'following', 0, 'friends', 0, 'posts', 0);
  END IF;

  SELECT count(*) INTO v_followers FROM public.follows WHERE following_id = p_user_id;
  SELECT count(*) INTO v_following FROM public.follows WHERE follower_id = p_user_id;
  SELECT count(*) INTO v_friends
  FROM public.follows f
  JOIN public.follows b
    ON b.follower_id = f.following_id AND b.following_id = f.follower_id
  WHERE f.follower_id = p_user_id;
  SELECT count(*) INTO v_posts
  FROM public.posts WHERE user_id = p_user_id AND is_active = true;

  RETURN jsonb_build_object(
    'followers', v_followers,
    'following', v_following,
    'friends', v_friends,
    'posts', v_posts
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_follow_counts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_follow_counts(uuid) TO anon, authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
