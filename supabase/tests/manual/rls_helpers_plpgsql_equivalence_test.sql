-- =============================================================================
-- Eşdeğerlik + hız testi: 20261005000001_rls_helpers_plpgsql_plan_cache
-- =============================================================================
-- Çalıştır:  supabase db query --linked --file supabase/tests/manual/rls_helpers_plpgsql_equivalence_test.sql
-- Her şey tek işlemde olur ve sonda GERİ ALINIR (canlı veriye/şemaya iz kalmaz).
--
-- 1) Fikstür: bir engelleme, bir içerik moderatörü (yönetici olmayan), bir
--    Okey izleyicisi eklenir — canlıda hiç olmayan dallar da sınansın.
-- 2) Yardımcıların ESKİ (LANGUAGE sql) tanımları kurulur; her rol × etkilenen
--    her tablo için görünür satır kümesi (count + ctid md5) ve süre alınır.
-- 3) Göçün YENİ (plpgsql) tanımları kurulur; aynı ölçüm tekrarlanır.
-- 4) Fark varsa listelenir; sonuç RAISE EXCEPTION 'RLS_EQ ...' ile basılır
--    (istisna işlemi geri alır). "mismatches=0" beklenir.
-- Bu dosya scratchpad/gen_rls_test.js ile göçten üretildi.

BEGIN;

CREATE TEMP TABLE _rls_users (who text, role text, claims text) ON COMMIT DROP;
CREATE TEMP TABLE _rls_probes (label text, sql text) ON COMMIT DROP;
CREATE TEMP TABLE _rls_snap (phase text, who text, label text, n bigint, h text, ms numeric) ON COMMIT DROP;

DO $fixture$
DECLARE
  v_admin uuid;
  v_seller uuid := '9a4ff88e-bacf-41a7-9da8-e70d1bba9fa5';
  v_courier uuid;
  v_private uuid;
  v_private_follower uuid;
  v_moderator uuid;
  v_spectator uuid;
  v_plain uuid;
  v_blocked uuid;
  v_room uuid;
  v_fn text;
BEGIN
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_courier FROM public.profiles WHERE role::text = 'courier' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_private FROM public.profiles
   WHERE profile_is_public = false AND COALESCE(is_bot, false) = false ORDER BY created_at LIMIT 1;
  SELECT f.follower_id INTO v_private_follower FROM public.follows f
   WHERE f.following_id = v_private LIMIT 1;
  -- Engellenen: satıcı dışındaki en çok gönderisi olan yazar
  SELECT user_id INTO v_blocked FROM public.posts
   WHERE user_id <> v_seller GROUP BY user_id ORDER BY count(*) DESC LIMIT 1;
  SELECT id INTO v_moderator FROM public.profiles
   WHERE role::text = 'customer' AND COALESCE(is_bot, false) = false
     AND status::text = 'active'
   ORDER BY created_at LIMIT 1;
  SELECT id INTO v_plain FROM public.profiles
   WHERE role::text = 'customer' AND COALESCE(is_bot, false) = false
     AND id NOT IN (v_moderator, COALESCE(v_private_follower, v_moderator))
   ORDER BY created_at DESC LIMIT 1;
  v_spectator := v_plain;
  -- İzleyici: oturmadığı, en çok hamlesi olan masa
  SELECT m.room_id INTO v_room FROM public.okey_moves mv
    JOIN public.okey_matches m ON m.id = mv.match_id
   WHERE NOT EXISTS (SELECT 1 FROM public.okey_room_players rp
                      WHERE rp.room_id = m.room_id AND rp.user_id = v_spectator)
   GROUP BY m.room_id ORDER BY count(*) DESC LIMIT 1;

  INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (v_seller, v_blocked);
  INSERT INTO public.moderators (user_id, scopes) VALUES (v_moderator, ARRAY['content']);
  INSERT INTO public.okey_room_spectators (room_id, user_id) VALUES (v_room, v_spectator);

  INSERT INTO _rls_users VALUES
    ('anon', 'anon', json_build_object('role', 'anon')::text),
    ('admin', 'authenticated', json_build_object('sub', v_admin, 'role', 'authenticated')::text),
    ('seller_blocker', 'authenticated', json_build_object('sub', v_seller, 'role', 'authenticated')::text),
    ('blocked_author', 'authenticated', json_build_object('sub', v_blocked, 'role', 'authenticated')::text),
    ('courier', 'authenticated', json_build_object('sub', v_courier, 'role', 'authenticated')::text),
    ('private_user', 'authenticated', json_build_object('sub', v_private, 'role', 'authenticated')::text),
    ('moderator', 'authenticated', json_build_object('sub', v_moderator, 'role', 'authenticated')::text),
    ('spectator_plain', 'authenticated', json_build_object('sub', v_spectator, 'role', 'authenticated')::text);
  IF v_private_follower IS NOT NULL THEN
    INSERT INTO _rls_users VALUES ('private_follower', 'authenticated',
      json_build_object('sub', v_private_follower, 'role', 'authenticated')::text);
  END IF;

  -- Etkilenen tablolar: politikası dönüştürülen yardımcılardan birini çağıran her tablo
  INSERT INTO _rls_probes
  SELECT DISTINCT p.tablename,
         format('select count(*), md5(coalesce(string_agg(ctid::text, '','' order by ctid), '''')) from public.%I', p.tablename)
    FROM pg_policies p
   WHERE p.schemaname = 'public'
     AND (coalesce(p.qual, '') || ' ' || coalesce(p.with_check, ''))
         ~ ('(current_user_is_admin|auth_is_admin|is_admin|ilan_is_admin|social_is_admin|is_courier_role|current_user_role_in_list|auth_is_moderator|social_block_exists|can_view_social_author|social_can_follow_directly|is_seated_in_okey_room|is_seated_in_okey_match|can_view_okey_room|can_view_okey_match)\(');

  -- Dalları doğrudan yoklayan sondalar
  INSERT INTO _rls_probes VALUES
    ('probe:posts_of_blocked_author', format('select count(*), '''' from public.posts where user_id = %L', v_blocked)),
    ('probe:posts_of_private_user', format('select count(*), '''' from public.posts where user_id = %L', v_private)),
    ('probe:inactive_posts', 'select count(*), '''' from public.posts where is_active = false'),
    ('probe:spectated_room_moves', format('select count(*), '''' from public.okey_moves mv join public.okey_matches m on m.id = mv.match_id where m.room_id = %L', v_room)),
    ('probe:feed_page_20', 'select count(*), md5(coalesce(string_agg(id::text, '','' order by admin_pinned desc nulls last, created_at desc nulls last), '''')) from (select * from public.posts_with_profiles order by admin_pinned desc nulls last, created_at desc nulls last limit 20) x');
END
$fixture$;

CREATE FUNCTION pg_temp.rls_snap(p_phase text) RETURNS void
LANGUAGE plpgsql AS $snap$
DECLARE
  u record;
  t record;
  v_n bigint;
  v_h text;
  v_t0 timestamptz;
  v_ms numeric;
  v_me text := current_user;
BEGIN
  FOR u IN SELECT * FROM _rls_users LOOP
    FOR t IN SELECT * FROM _rls_probes ORDER BY label LOOP
      PERFORM set_config('request.jwt.claims', u.claims, true);
      PERFORM set_config('role', u.role, true);
      BEGIN
        v_t0 := clock_timestamp();
        EXECUTE t.sql INTO v_n, v_h;
        v_ms := extract(epoch FROM clock_timestamp() - v_t0) * 1000;
      EXCEPTION WHEN insufficient_privilege THEN
        v_n := -1; v_h := 'denied'; v_ms := 0;
      END;
      PERFORM set_config('role', v_me, true);
      INSERT INTO _rls_snap VALUES (p_phase, u.who, t.label, v_n, v_h, v_ms);
    END LOOP;
  END LOOP;
END
$snap$;

-- -----------------------------------------------------------------------------
-- ESKİ tanımlar (göç öncesi canlı hâl, LANGUAGE sql)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.current_user_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role = 'admin'::public.user_role
  );
$function$;

CREATE OR REPLACE FUNCTION public.auth_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
        SELECT private.current_user_is_admin();
      $function$;

CREATE OR REPLACE FUNCTION public.ilan_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND (p.role::text = 'admin' OR COALESCE(p.is_admin, false))
  );
$function$;

CREATE OR REPLACE FUNCTION public.social_is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND (p.role = 'admin' OR p.is_admin = true)
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_courier_role()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = (SELECT auth.uid())
      AND p.role::text = 'courier'
  );
$function$;

CREATE OR REPLACE FUNCTION public.current_user_role_in_list(target_roles text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
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
$function$;

CREATE OR REPLACE FUNCTION public.auth_is_moderator(p_scope text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT private.current_user_is_admin()
      OR EXISTS (
           SELECT 1
             FROM public.moderators m
             JOIN public.profiles p ON p.id = m.user_id
            WHERE m.user_id = (SELECT auth.uid())
              AND p.status::text = 'active'
              AND (p_scope IS NULL OR p_scope = ANY (m.scopes))
         );
$function$;

CREATE OR REPLACE FUNCTION public.social_block_exists(p_other uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.blocked_users b
    WHERE (b.blocker_id = (SELECT auth.uid()) AND b.blocked_id = p_other)
       OR (b.blocker_id = p_other AND b.blocked_id = (SELECT auth.uid()))
  );
$function$;

CREATE OR REPLACE FUNCTION public.can_view_social_author(p_author uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.social_can_follow_directly(p_target uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT p_target IS NOT NULL
     AND p_target IS DISTINCT FROM (SELECT auth.uid())
     AND COALESCE(
           (SELECT COALESCE(pr.profile_is_public, true) FROM public.profiles pr WHERE pr.id = p_target),
           false
         )
     AND NOT public.social_block_exists(p_target);
$function$;

CREATE OR REPLACE FUNCTION public.is_seated_in_okey_room(p_room_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = (SELECT auth.uid())
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_seated_in_okey_match(p_match_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    JOIN public.okey_matches AS m ON m.room_id = rp.room_id
    WHERE m.id = p_match_id AND rp.user_id = (SELECT auth.uid())
  );
$function$;

CREATE OR REPLACE FUNCTION public.can_view_okey_room(p_room_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT public.is_seated_in_okey_room(p_room_id)
      OR EXISTS (
        SELECT 1 FROM public.okey_room_spectators AS s
        WHERE s.room_id = p_room_id AND s.user_id = (SELECT auth.uid())
      );
$function$;

CREATE OR REPLACE FUNCTION public.can_view_okey_match(p_match_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT public.is_seated_in_okey_match(p_match_id)
      OR EXISTS (
        SELECT 1
        FROM public.okey_matches AS m
        JOIN public.okey_room_spectators AS s ON s.room_id = m.room_id
        WHERE m.id = p_match_id AND s.user_id = (SELECT auth.uid())
      );
$function$;

SELECT pg_temp.rls_snap('before');

-- -----------------------------------------------------------------------------
-- YENİ tanımlar (göç gövdesi, LANGUAGE plpgsql)
-- -----------------------------------------------------------------------------
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

SELECT pg_temp.rls_snap('after');

DO $report$
DECLARE
  v_bad text;
  v_bad_n int;
  v_pairs int;
  v_timing text;
  v_probes text;
  v_lang text;
BEGIN
  SELECT count(*), string_agg(format('%s / %s: before n=%s after n=%s', b.who, b.label, b.n, a.n), E'\n')
    INTO v_bad_n, v_bad
    FROM _rls_snap b
    JOIN _rls_snap a ON a.who = b.who AND a.label = b.label AND a.phase = 'after'
   WHERE b.phase = 'before' AND (a.n IS DISTINCT FROM b.n OR a.h IS DISTINCT FROM b.h);

  SELECT count(*) INTO v_pairs FROM _rls_snap WHERE phase = 'before';

  SELECT string_agg(format('%s  before %s ms -> after %s ms', rpad(label, 34), round(bm, 1), round(am, 1)), E'\n' ORDER BY bm DESC)
    INTO v_timing
    FROM (SELECT label,
                 sum(ms) FILTER (WHERE phase = 'before') AS bm,
                 sum(ms) FILTER (WHERE phase = 'after') AS am
            FROM _rls_snap GROUP BY label) x
   WHERE bm > 2;

  SELECT string_agg(format('%s %s n=%s', rpad(who, 18), label, n), E'\n' ORDER BY label, who)
    INTO v_probes
    FROM _rls_snap WHERE phase = 'after' AND label LIKE 'probe:%';

  SELECT string_agg(DISTINCT l.lanname, ',') INTO v_lang
    FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
   WHERE p.proname IN ('current_user_is_admin', 'auth_is_admin', 'is_admin', 'ilan_is_admin', 'social_is_admin', 'is_courier_role', 'current_user_role_in_list', 'auth_is_moderator', 'social_block_exists', 'can_view_social_author', 'social_can_follow_directly', 'is_seated_in_okey_room', 'is_seated_in_okey_match', 'can_view_okey_room', 'can_view_okey_match');

  RAISE EXCEPTION E'RLS_EQ mismatches=% pairs=% languages_now=%\n--- mismatches ---\n%\n--- timing (sum over roles) ---\n%\n--- probes (after) ---\n%',
    v_bad_n, v_pairs, v_lang, coalesce(v_bad, '(none)'), v_timing, v_probes;
END
$report$;

ROLLBACK;
