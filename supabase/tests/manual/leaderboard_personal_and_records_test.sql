-- Görev 4.4 — "Rakamlarla Sen" ve "Rekor Skorlar" canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/leaderboard_personal_and_records_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey (ayarlar dahil) geri alınır.
-- Canlıda leaderboard_enabled KAPALI olabilir: test işlem içinde açar.
DO $test$
DECLARE
  v_user uuid;
  v_anon uuid;
  v_json jsonb;
  v_stats jsonb;
  v_records jsonb;
  v_expected bigint;
  v_day date;
  v_id uuid;
  v_state text;
  v_checks integer := 0;
BEGIN
  UPDATE public.app_settings SET value = '"true"'::jsonb
   WHERE key IN ('leaderboard_enabled', 'leaderboard_board_my_stats', 'leaderboard_board_records')
      OR key LIKE 'leaderboard_stat_my_%' OR key LIKE 'leaderboard_record_%';

  SELECT p.id INTO v_user
    FROM public.profiles p
   WHERE NOT COALESCE(p.is_bot, false) AND p.status::text = 'active'
     AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)
     AND EXISTS (SELECT 1 FROM public.posts x WHERE x.user_id = p.id AND x.is_active IS NOT FALSE)
   ORDER BY p.created_at LIMIT 1;
  SELECT a.id INTO v_anon FROM auth.users a JOIN public.profiles p ON p.id = a.id WHERE a.is_anonymous LIMIT 1;
  IF v_user IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;

  -- [1] ayarlar: yeni kartlar 'stats_today'dan sonra; kişisel sayaç ve rekor anahtarları
  v_json := public.leaderboard_settings();
  IF (public.leaderboard_card_keys())[3:4] <> ARRAY['my_stats', 'records']
     OR NOT (v_json -> 'boards' ? 'my_stats') OR NOT (v_json -> 'boards' ? 'records')
     OR (SELECT count(*) FROM jsonb_object_keys(v_json -> 'records')) <> 8
     OR (SELECT count(*) FROM jsonb_object_keys(v_json -> 'stats') k WHERE k LIKE 'my\_%') <> 10 THEN
    RAISE EXCEPTION '[1] ayarlar: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [2] kişisel sayılar bağımsız hesaplarla aynı
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_json := public.get_leaderboards();
  EXECUTE 'RESET ROLE';
  v_stats := v_json -> 'stats';
  IF (v_stats ->> 'my_posts')::bigint IS DISTINCT FROM
       (SELECT count(*) FROM public.posts x WHERE x.user_id = v_user AND x.is_active IS NOT FALSE)
     OR (v_stats ->> 'my_likes')::bigint IS DISTINCT FROM
       (SELECT COALESCE(sum(COALESCE(x.likes_count, 0)), 0) FROM public.posts x
         WHERE x.user_id = v_user AND x.is_active IS NOT FALSE)
     OR (v_stats ->> 'my_followers')::bigint IS DISTINCT FROM
       (SELECT count(*) FROM public.follows f WHERE f.following_id = v_user)
     OR (v_stats ->> 'my_following')::bigint IS DISTINCT FROM
       (SELECT count(*) FROM public.follows f WHERE f.follower_id = v_user)
     OR (v_stats ->> 'my_days')::int IS DISTINCT FROM
       (SELECT (now() AT TIME ZONE 'Europe/Istanbul')::date - (p.created_at AT TIME ZONE 'Europe/Istanbul')::date
          FROM public.profiles p WHERE p.id = v_user)
     OR (v_stats ->> 'my_okey_matches')::int IS DISTINCT FROM
       COALESCE((SELECT s.matches_played FROM public.okey_stats s WHERE s.user_id = v_user), 0)
     OR NOT (v_stats ? 'my_orders') OR NOT (v_stats ? 'my_logins') OR NOT (v_stats ? 'my_post_views') THEN
    RAISE EXCEPTION '[2] kişisel sayılar: %', v_stats;
  END IF;
  v_checks := v_checks + 1;

  -- [3] rekorlar: en kalabalık gün ve tek günde en çok yeni üye bağımsız hesapla aynı
  v_records := v_json -> 'records';
  WITH seen AS (
    SELECT l.user_id AS uid, (l.created_at AT TIME ZONE 'Europe/Istanbul')::date AS d
      FROM public.user_activity_logs l WHERE l.user_id IS NOT NULL
    UNION
    SELECT e.user_id, (e.created_at AT TIME ZONE 'Europe/Istanbul')::date
      FROM public.app_analytics_events e WHERE e.user_id IS NOT NULL
    UNION
    SELECT p.id, (p.last_seen AT TIME ZONE 'Europe/Istanbul')::date FROM public.profiles p WHERE p.last_seen IS NOT NULL
  )
  SELECT max(c) INTO v_expected FROM (
    SELECT count(DISTINCT s.uid) AS c FROM seen s JOIN public.profiles p ON p.id = s.uid
     WHERE NOT COALESCE(p.is_bot, false) AND p.status::text = 'active' GROUP BY s.d) t;
  IF (v_records -> 'busiest_day' ->> 'value')::bigint IS DISTINCT FROM v_expected
     OR v_records -> 'busiest_day' ->> 'type' <> 'day' THEN
    RAISE EXCEPTION '[3] en kalabalık gün: % (beklenen %)', v_records -> 'busiest_day', v_expected;
  END IF;
  SELECT max(c) INTO v_expected FROM (
    SELECT count(*) AS c FROM public.profiles p
     WHERE NOT COALESCE(p.is_bot, false) AND p.status::text = 'active'
       AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)
     GROUP BY (p.created_at AT TIME ZONE 'Europe/Istanbul')::date) t;
  IF (v_records -> 'signup_day' ->> 'value')::bigint IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION '[3] yeni üye rekoru: % (beklenen %)', v_records -> 'signup_day', v_expected;
  END IF;
  v_checks := v_checks + 1;

  -- [4] kişi/gönderi rekorları: en eski üye yönetici değil, en çok beğenilen ve ilk gönderi doğru
  SELECT e.e_id INTO v_id
    FROM public.leaderboard_eligible_users() e JOIN public.profiles p ON p.id = e.e_id
   WHERE p.role::text <> 'admin' AND NOT COALESCE(p.is_admin, false)
   ORDER BY e.e_created_at, e.e_id LIMIT 1;
  IF (v_records -> 'oldest_member' ->> 'id')::uuid IS DISTINCT FROM v_id
     OR v_records -> 'oldest_member' ->> 'type' <> 'user' THEN
    RAISE EXCEPTION '[4] en eski üye: % (beklenen %)', v_records -> 'oldest_member', v_id;
  END IF;
  SELECT po.id INTO v_id FROM public.posts po
    JOIN public.leaderboard_eligible_users() e ON e.e_id = po.user_id
   WHERE po.is_active IS NOT FALSE AND COALESCE(po.likes_count, 0) > 0
   ORDER BY po.likes_count DESC, po.created_at DESC, po.id LIMIT 1;
  IF (v_records -> 'top_post_likes' ->> 'id')::uuid IS DISTINCT FROM v_id THEN
    RAISE EXCEPTION '[4] en çok beğenilen: % (beklenen %)', v_records -> 'top_post_likes', v_id;
  END IF;
  SELECT po.id INTO v_id FROM public.posts po
    JOIN public.leaderboard_eligible_users() e ON e.e_id = po.user_id
   WHERE po.is_active IS NOT FALSE ORDER BY po.created_at, po.id LIMIT 1;
  IF (v_records -> 'first_post' ->> 'id')::uuid IS DISTINCT FROM v_id
     OR v_records -> 'first_post' ->> 'owner' IS NULL THEN
    RAISE EXCEPTION '[4] ilk gönderi: % (beklenen %)', v_records -> 'first_post', v_id;
  END IF;
  v_checks := v_checks + 1;

  -- [5] anahtarlar: kapalı sayaç/rekor dönmez; kart kapalıysa hiçbiri
  UPDATE public.app_settings SET value = '"false"'::jsonb
   WHERE key IN ('leaderboard_stat_my_posts', 'leaderboard_record_first_post');
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_json := public.get_leaderboards();
  EXECUTE 'RESET ROLE';
  IF v_json -> 'stats' ? 'my_posts' OR NOT (v_json -> 'stats' ? 'my_likes')
     OR v_json -> 'records' ? 'first_post' OR NOT (v_json -> 'records' ? 'busiest_day') THEN
    RAISE EXCEPTION '[5] tek anahtar: %', v_json -> 'stats';
  END IF;
  UPDATE public.app_settings SET value = '"false"'::jsonb
   WHERE key IN ('leaderboard_board_my_stats', 'leaderboard_board_records');
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_json := public.get_leaderboards();
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM jsonb_object_keys(v_json -> 'stats') k WHERE k LIKE 'my\_%') > 0
     OR v_json -> 'records' <> '{}'::jsonb THEN
    RAISE EXCEPTION '[5] kart kapalı: %', v_json;
  END IF;
  UPDATE public.app_settings SET value = '"true"'::jsonb
   WHERE key IN ('leaderboard_board_my_stats', 'leaderboard_board_records');
  v_checks := v_checks + 1;

  -- [6] misafir (anonim) hesaba kişisel sayı dönmez
  IF v_anon IS NOT NULL THEN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_anon, 'role', 'authenticated')::text, true);
    v_json := public.get_leaderboards();
    EXECUTE 'RESET ROLE';
    IF (SELECT count(*) FROM jsonb_object_keys(v_json -> 'stats') k WHERE k LIKE 'my\_%') > 0 THEN
      RAISE EXCEPTION '[6] misafire kişisel sayı döndü: %', v_json -> 'stats';
    END IF;
  END IF;
  v_checks := v_checks + 1;

  -- [7] yardımcılar istemciye kapalı
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    PERFORM public.leaderboard_records();
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[7] rekorlar doğrudan çağrıldı: %', v_state; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
