-- =============================================================================
-- Görev 3.5 — Takip altyapısının sağlamlaştırılması + "Önerilen Kişiler"
-- =============================================================================
-- Takip tabloları (follows, follow_requests) zaten vardı. Canlıda bulunan açıklar:
--   * `follows_insert_self` yalnız "kendin adına" diyordu → herkes GİZLİ bir
--     hesabı istek/onay olmadan doğrudan takip edebiliyordu; gizli hesabın
--     gönderileri `can_view_social_author` ile "takipçiye açık" olduğu için bu
--     gizliliği tamamen deliyordu (sohbet üyeleri ekranı bunu kendisi yapıyordu).
--   * Engellenen kişi engelleyeni takip edip "seni takip etti" bildirimi
--     gönderebiliyordu.
--   * follow_requests'e doğrudan status='accepted' eklenebiliyordu.
--   * upsert_follow_request INVOKER'dı: reddedilmiş isteği "tekrar gönderdim"
--     derken UPDATE RLS'e takılıp hiçbir şey yapmıyordu (hedefe bildirim yok).
--
-- Bu göç:
--   1) Doğrudan takip (follows INSERT) yalnız herkese açık + engelsiz hesaba;
--      gizli hesap yalnız istek → onay (mevcut DEFINER tetikleyici) ile.
--   2) social_follow(user, follow): tek RPC — açık hesabı takip eder, gizliye
--      istek gönderir, takibi bırakınca bekleyen isteği de geri alır.
--   3) upsert_follow_request DEFINER + çağıran doğrulaması; yeniden istek
--      silip-ekleyerek hedefe tekrar bildirim üretir.
--   4) Önerilen kişiler: suggested_follows(limit) — seni takip edenler,
--      ortak takipler, popülerlik, son 30 günde paylaşım; bot/admin/engelli/
--      takip edilen/bekleyen/60 gün içinde "kaldır"ılan hariç.
--      dismiss_follow_suggestion(user) ile kart kapatılır.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Doğrudan takip kuralı
-- -----------------------------------------------------------------------------
-- Politika ifadesi çağıranın yetkisiyle çalışır; profiles/blocked_users
-- okumaları DEFINER yardımcıda (RLS/sütun yetkisine takılmasın).
CREATE OR REPLACE FUNCTION public.social_can_follow_directly(p_target uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT p_target IS NOT NULL
     AND p_target IS DISTINCT FROM (SELECT auth.uid())
     AND COALESCE(
           (SELECT COALESCE(pr.profile_is_public, true) FROM public.profiles pr WHERE pr.id = p_target),
           false
         )
     AND NOT public.social_block_exists(p_target);
$fn$;

REVOKE ALL ON FUNCTION public.social_can_follow_directly(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.social_can_follow_directly(uuid) TO authenticated;

DROP POLICY IF EXISTS follows_insert_self ON public.follows;
CREATE POLICY follows_insert_self ON public.follows
  FOR INSERT TO authenticated
  WITH CHECK (
    follower_id = (SELECT auth.uid())
    AND public.social_can_follow_directly(following_id)
  );

-- İstek yalnız "bekliyor" olarak, kendin adına ve engelsiz hesaba açılır.
DROP POLICY IF EXISTS "Users can create follow requests" ON public.follow_requests;
CREATE POLICY "Users can create follow requests" ON public.follow_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    follower_id = (SELECT auth.uid())
    AND following_id IS DISTINCT FROM follower_id
    AND status = 'pending'
    AND NOT public.social_block_exists(following_id)
  );

-- -----------------------------------------------------------------------------
-- 2) Tek takip RPC'si
-- -----------------------------------------------------------------------------
-- Dönüş: {status: 'following' | 'requested' | 'none', followers_count}
CREATE OR REPLACE FUNCTION public.social_follow(p_user_id uuid, p_follow boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_me uuid := auth.uid();
  v_public boolean;
  v_request public.follow_requests%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Takip için giriş yapmalısın' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  IF p_user_id IS NULL OR p_user_id = v_me THEN
    RAISE EXCEPTION 'Kendini takip edemezsin' USING ERRCODE = 'P0001', HINT = 'FOLLOW_SELF';
  END IF;
  SELECT COALESCE(p.profile_is_public, true) INTO v_public
    FROM public.profiles p WHERE p.id = p_user_id;
  IF v_public IS NULL THEN
    RAISE EXCEPTION 'Kullanıcı bulunamadı' USING ERRCODE = 'P0001', HINT = 'FOLLOW_NOT_FOUND';
  END IF;

  IF p_follow THEN
    IF public.social_block_exists(p_user_id) THEN
      RAISE EXCEPTION 'Bu kullanıcıyı takip edemezsin' USING ERRCODE = 'P0001', HINT = 'FOLLOW_BLOCKED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = v_me AND f.following_id = p_user_id) THEN
      IF v_public THEN
        INSERT INTO public.follows (follower_id, following_id)
        VALUES (v_me, p_user_id)
        ON CONFLICT (follower_id, following_id) DO NOTHING;
      ELSE
        SELECT * INTO v_request FROM public.follow_requests r
         WHERE r.follower_id = v_me AND r.following_id = p_user_id
         FOR UPDATE;
        IF NOT FOUND OR v_request.status <> 'pending' THEN
          -- Reddedilmiş/eskimiş istek silinip yeniden açılır → hedef yine bildirim alır.
          DELETE FROM public.follow_requests r
           WHERE r.follower_id = v_me AND r.following_id = p_user_id;
          INSERT INTO public.follow_requests (follower_id, following_id, status)
          VALUES (v_me, p_user_id, 'pending');
        END IF;
      END IF;
    END IF;
  ELSE
    DELETE FROM public.follows f WHERE f.follower_id = v_me AND f.following_id = p_user_id;
    DELETE FROM public.follow_requests r
     WHERE r.follower_id = v_me AND r.following_id = p_user_id AND r.status = 'pending';
  END IF;

  RETURN jsonb_build_object(
    'status', CASE
      WHEN EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = v_me AND f.following_id = p_user_id)
        THEN 'following'
      WHEN EXISTS (SELECT 1 FROM public.follow_requests r
                    WHERE r.follower_id = v_me AND r.following_id = p_user_id AND r.status = 'pending')
        THEN 'requested'
      ELSE 'none'
    END,
    'followers_count', (SELECT count(*) FROM public.follows f WHERE f.following_id = p_user_id)
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.social_follow(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.social_follow(uuid, boolean) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) upsert_follow_request — aynı imza ve mesajlar; DEFINER + çağıran doğrulaması
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_follow_request(p_follower_id uuid, p_following_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_me uuid := auth.uid();
  v_request public.follow_requests%ROWTYPE;
BEGIN
  IF v_me IS NULL OR p_follower_id IS DISTINCT FROM v_me THEN
    RETURN jsonb_build_object('success', false, 'message', 'Bu işlem için yetkiniz yok');
  END IF;
  IF p_follower_id = p_following_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'Kendinizi takip edemezsiniz');
  END IF;
  IF public.social_block_exists(p_following_id) THEN
    RETURN jsonb_build_object('success', false, 'message', 'Bu kullanıcıyı takip edemezsiniz');
  END IF;
  IF EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = v_me AND f.following_id = p_following_id) THEN
    RETURN jsonb_build_object('success', false, 'message', 'Zaten takip ediyorsunuz', 'status', 'accepted');
  END IF;

  SELECT * INTO v_request FROM public.follow_requests r
   WHERE r.follower_id = v_me AND r.following_id = p_following_id
   FOR UPDATE;

  IF FOUND AND v_request.status = 'pending' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Zaten bekleyen bir istek var', 'status', 'pending');
  END IF;

  IF FOUND THEN
    -- Reddedilmiş ya da takibi kalkmış eski onay: yeniden istek (hedef yine onaylar).
    DELETE FROM public.follow_requests r WHERE r.id = v_request.id;
    INSERT INTO public.follow_requests (follower_id, following_id, status)
    VALUES (v_me, p_following_id, 'pending');
    RETURN jsonb_build_object('success', true, 'message', 'Takip isteği tekrar gönderildi', 'status', 'pending');
  END IF;

  INSERT INTO public.follow_requests (follower_id, following_id, status)
  VALUES (v_me, p_following_id, 'pending');
  RETURN jsonb_build_object('success', true, 'message', 'Takip isteği gönderildi', 'status', 'pending');
END;
$fn$;

REVOKE ALL ON FUNCTION public.upsert_follow_request(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_follow_request(uuid, uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) Önerilen kişiler
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.follow_suggestion_dismissals (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  dismissed_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, dismissed_user_id)
);
ALTER TABLE public.follow_suggestion_dismissals ENABLE ROW LEVEL SECURITY;
-- İstemci tabloya doğrudan erişmez (yalnız aşağıdaki RPC'ler).
REVOKE ALL ON public.follow_suggestion_dismissals FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.dismiss_follow_suggestion(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Giriş yapmalısın' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  IF p_user_id IS NULL OR p_user_id = v_me THEN
    RETURN;
  END IF;
  INSERT INTO public.follow_suggestion_dismissals (user_id, dismissed_user_id)
  VALUES (v_me, p_user_id)
  ON CONFLICT (user_id, dismissed_user_id) DO UPDATE SET created_at = now();
END;
$fn$;

-- Sıralama puanı: seni takip ediyor (1000) > ortak takip (40/kişi, en çok 20)
-- > takipçi (2/kişi, en çok 100) > son 30 günde paylaşım (60) > doğrulanmış (30)
-- > fotoğraflı (25) > son 14 günün yeni üyesi (20) + her gün değişen küçük
-- karıştırma (0–29) — öneriler günden güne dönsün.
CREATE OR REPLACE FUNCTION public.suggested_follows(p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_me uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 30);
  v_result jsonb;
BEGIN
  IF v_me IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  WITH my_following AS (
    SELECT f.following_id AS id FROM public.follows f WHERE f.follower_id = v_me
  ),
  candidates AS (
    SELECT p.id, p.username, p.full_name, p.avatar_url, p.created_at,
           COALESCE(p.is_verified, false) AS is_verified,
           NOT COALESCE(p.profile_is_public, true) AS is_private
      FROM public.profiles p
     WHERE p.id <> v_me
       AND p.status::text = 'active'
       AND NOT COALESCE(p.is_bot, false)
       AND NOT COALESCE(p.is_admin, false)
       AND p.role::text <> 'admin'
       AND NOT COALESCE(p.is_suspicious, false)
       AND NOT COALESCE(p.needs_username, false)
       AND NULLIF(btrim(p.username), '') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM my_following mf WHERE mf.id = p.id)
       AND NOT EXISTS (SELECT 1 FROM public.follow_requests r
                        WHERE r.follower_id = v_me AND r.following_id = p.id AND r.status = 'pending')
       AND NOT EXISTS (SELECT 1 FROM public.blocked_users b
                        WHERE (b.blocker_id = v_me AND b.blocked_id = p.id)
                           OR (b.blocker_id = p.id AND b.blocked_id = v_me))
       AND NOT EXISTS (SELECT 1 FROM public.follow_suggestion_dismissals d
                        WHERE d.user_id = v_me AND d.dismissed_user_id = p.id
                          AND d.created_at > now() - interval '60 days')
  ),
  scored AS (
    SELECT c.*,
           EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = c.id AND f.following_id = v_me) AS follows_you,
           (SELECT count(*) FROM public.follows f JOIN my_following mf ON mf.id = f.follower_id
             WHERE f.following_id = c.id)::integer AS mutual_count,
           (SELECT count(*) FROM public.follows f WHERE f.following_id = c.id)::integer AS followers_count,
           EXISTS (SELECT 1 FROM public.posts po
                    WHERE po.user_id = c.id AND COALESCE(po.is_active, true)
                      AND po.created_at > now() - interval '30 days') AS recently_active
      FROM candidates c
  ),
  ranked AS (
    SELECT s.*,
           (CASE WHEN s.follows_you THEN 1000 ELSE 0 END)
           + LEAST(s.mutual_count, 20) * 40
           + LEAST(s.followers_count, 100) * 2
           + (CASE WHEN s.recently_active THEN 60 ELSE 0 END)
           + (CASE WHEN s.is_verified THEN 30 ELSE 0 END)
           + (CASE WHEN s.avatar_url IS NOT NULL THEN 25 ELSE 0 END)
           + (CASE WHEN s.created_at > now() - interval '14 days' THEN 20 ELSE 0 END)
           + (abs(hashtext(s.id::text || current_date::text)::bigint) % 30) AS score
      FROM scored s
  ),
  top AS (
    SELECT * FROM ranked ORDER BY score DESC, id LIMIT v_limit
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', t.id,
           'username', t.username,
           'full_name', t.full_name,
           'avatar_url', t.avatar_url,
           'is_verified', t.is_verified,
           'is_private', t.is_private,
           'followers_count', t.followers_count,
           'mutual_count', t.mutual_count,
           'follows_you', t.follows_you,
           'mutual_names', COALESCE((
             SELECT jsonb_agg(x.username)
               FROM (SELECT p2.username
                       FROM public.follows f2
                       JOIN my_following mf2 ON mf2.id = f2.follower_id
                       JOIN public.profiles p2 ON p2.id = f2.follower_id
                      WHERE f2.following_id = t.id
                      ORDER BY f2.created_at DESC
                      LIMIT 2) x
           ), '[]'::jsonb),
           'reason', CASE
             WHEN t.follows_you THEN 'follows_you'
             WHEN t.mutual_count > 0 THEN 'mutual'
             WHEN t.followers_count >= 10 THEN 'popular'
             WHEN t.created_at > now() - interval '14 days' THEN 'new'
             ELSE 'suggested'
           END
         ) ORDER BY t.score DESC, t.id), '[]'::jsonb)
    INTO v_result
    FROM top t;

  RETURN v_result;
END;
$fn$;

REVOKE ALL ON FUNCTION public.dismiss_follow_suggestion(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.suggested_follows(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dismiss_follow_suggestion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.suggested_follows(integer) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
