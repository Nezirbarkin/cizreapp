-- =============================================================================
-- Performans: RLS yardımcı fonksiyonları LANGUAGE sql → plpgsql
-- =============================================================================
--
-- Sorun: RLS politikalarının satır başına çağırdığı yardımcılar
-- "LANGUAGE sql + SECURITY DEFINER + SET search_path" idi. SET seçeneği olan
-- SQL fonksiyonu satır içine açılamaz (inline) ve her çağrıda yeniden
-- planlanır. Canlı ölçüm (normal kullanıcı, count(*), RLS'siz → RLS'li):
--   okey_moves        1,7 ms → 3370 ms   (can_view_okey_match, 12.7k satır)
--   okey_table_melds  0,3 ms →  623 ms
--   okey_room_players 0,2 ms →  116 ms   (can_view_okey_room)
--   posts             0,1 ms →   89 ms   (can_view_social_author; sosyal akış
--                                          sayfası posts_with_profiles ~97 ms)
-- plpgsql planları oturum boyunca önbellekler; aynı mantık çağrı başına
-- kat kat ucuzdur.
--
-- Değişen YALNIZ dildir: her fonksiyonun imzası, parametre adları/varsayılanı,
-- dönüş tipi, STABLE, SECURITY DEFINER ve search_path'i birebir korunur;
-- gövde, eski SELECT ifadesinin aynısını RETURN eder. CREATE OR REPLACE
-- sahipliği ve EXECUTE haklarını korur (GRANT yeniden verilmez — bazıları
-- anon'a bilerek kapalı, bkz. project_leftover_select_merged_policies).
--
-- Eşdeğerlik kanıtı: supabase/tests/manual/rls_helpers_plpgsql_equivalence_test.sql
-- (her rol × her etkilenen tablo için görünür satır kümesi önce/sonra aynı).

BEGIN;

-- -----------------------------------------------------------------------------
-- Yönetici / rol yardımcıları (argümansız)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.current_user_is_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role = 'admin'::public.user_role
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.auth_is_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN private.current_user_is_admin();
END;
$function$;

CREATE OR REPLACE FUNCTION public.ilan_is_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND (p.role::text = 'admin' OR COALESCE(p.is_admin, false))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.social_is_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND (p.role = 'admin' OR p.is_admin = true)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_courier_role()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = (SELECT auth.uid())
      AND p.role::text = 'courier'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.current_user_role_in_list(target_roles text[])
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  RETURN EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role::text = ANY(target_roles)
  )
  OR EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE u.id = auth.uid()
        AND (
            u.raw_user_meta_data->>'role' = ANY(target_roles)
            OR (u.raw_user_meta_data->'roles') ?| target_roles
        )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.auth_is_moderator(p_scope text DEFAULT NULL::text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN private.current_user_is_admin()
      OR EXISTS (
           SELECT 1
             FROM public.moderators m
             JOIN public.profiles p ON p.id = m.user_id
            WHERE m.user_id = (SELECT auth.uid())
              AND p.status::text = 'active'
              AND (p_scope IS NULL OR p_scope = ANY (m.scopes))
         );
END;
$function$;

-- -----------------------------------------------------------------------------
-- Sosyal görünürlük (posts / stories / follows / follow_requests)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.social_block_exists(p_other uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.blocked_users b
    WHERE (b.blocker_id = (SELECT auth.uid()) AND b.blocked_id = p_other)
       OR (b.blocker_id = p_other AND b.blocked_id = (SELECT auth.uid()))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.can_view_social_author(p_author uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN CASE
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
END;
$function$;

CREATE OR REPLACE FUNCTION public.social_can_follow_directly(p_target uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN p_target IS NOT NULL
     AND p_target IS DISTINCT FROM (SELECT auth.uid())
     AND COALESCE(
           (SELECT COALESCE(pr.profile_is_public, true) FROM public.profiles pr WHERE pr.id = p_target),
           false
         )
     AND NOT public.social_block_exists(p_target);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 101 Okey masa/maç görünürlüğü (okey_moves, okey_table_melds, okey_matches,
-- okey_room_players, okey_rooms, okey_room_spectators, okey_scores_history,
-- okey_gifts_sent)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_seated_in_okey_room(p_room_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = (SELECT auth.uid())
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_seated_in_okey_match(p_match_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    JOIN public.okey_matches AS m ON m.room_id = rp.room_id
    WHERE m.id = p_match_id AND rp.user_id = (SELECT auth.uid())
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.can_view_okey_room(p_room_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN public.is_seated_in_okey_room(p_room_id)
      OR EXISTS (
        SELECT 1 FROM public.okey_room_spectators AS s
        WHERE s.room_id = p_room_id AND s.user_id = (SELECT auth.uid())
      );
END;
$function$;

CREATE OR REPLACE FUNCTION public.can_view_okey_match(p_match_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN public.is_seated_in_okey_match(p_match_id)
      OR EXISTS (
        SELECT 1
        FROM public.okey_matches AS m
        JOIN public.okey_room_spectators AS s ON s.room_id = m.room_id
        WHERE m.id = p_match_id AND s.user_id = (SELECT auth.uid())
      );
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';
