-- Ana sayfada biten yayın 24 saat (hikâye gibi), "Yayınlarım" ve kullanıcı
-- yayınında bildirimin yalnız takipçilere gitmesi — canlı doğrulama
-- (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/live_home_story_window_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_host uuid; v_viewer uuid; v_fan uuid; v_other uuid;
  v_shop uuid; v_owner uuid;
  v_s uuid; v_s2 uuid; v_ss uuid;
  v_json jsonb;
  v_last jsonb;
  v_hint text;
  v_n integer;
  v_notified integer;
  v_checks integer := 0;
BEGIN
  SELECT s.id, s.owner_id INTO v_shop, v_owner
    FROM public.shops s
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) AND s.owner_id IS NOT NULL
   ORDER BY s.created_at LIMIT 1;

  -- Sıradan (mağazasız, bot olmayan, aktif, yönetici/moderatör olmayan) 4 hesap.
  SELECT to_jsonb(array_agg(id ORDER BY created_at)) INTO STRICT v_json
    FROM (SELECT p.id, p.created_at FROM public.profiles p
           WHERE p.status::text = 'active' AND NOT COALESCE(p.is_bot, false)
             AND p.role::text <> 'admin'
             AND NOT EXISTS (SELECT 1 FROM public.moderators m WHERE m.user_id = p.id)
             AND NOT EXISTS (SELECT 1 FROM public.shops s WHERE s.owner_id = p.id)
             AND NULLIF(btrim(p.username), '') IS NOT NULL
           ORDER BY p.created_at LIMIT 4) x;
  v_host := (v_json ->> 0)::uuid; v_viewer := (v_json ->> 1)::uuid;
  v_fan := (v_json ->> 2)::uuid; v_other := (v_json ->> 3)::uuid;
  IF v_shop IS NULL OR v_other IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;

  -- Temiz başlangıç (hepsi geri alınır)
  DELETE FROM public.live_sessions WHERE host_user_id IN (v_host, v_viewer);
  DELETE FROM public.user_live_permissions WHERE user_id = v_host;
  DELETE FROM public.live_notify_log WHERE host_user_id = v_host;
  DELETE FROM public.follows WHERE following_id = v_host AND follower_id IN (v_viewer, v_fan, v_other);
  DELETE FROM public.blocked_users WHERE (blocker_id = v_host AND blocked_id IN (v_viewer, v_fan, v_other))
                                      OR (blocked_id = v_host AND blocker_id IN (v_viewer, v_fan, v_other));
  DELETE FROM public.notification_preferences WHERE user_id IN (v_fan, v_other, v_viewer);
  UPDATE public.profiles SET profile_is_public = true WHERE id = v_host;
  INSERT INTO public.follows (follower_id, following_id) VALUES (v_fan, v_host), (v_other, v_host);
  INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (v_host, v_other);
  INSERT INTO public.app_settings (key, value)
  VALUES ('live_stream_enabled', '"true"'), ('live_notify_enabled', '"true"'),
         ('live_notify_user_followers', '"true"'), ('live_user_streams', '"open"'),
         ('live_home_card_enabled', '"true"'), ('live_history_days', '"30"')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  -- [1] kullanıcı yayını: bildirim yalnız (engellenmemiş) takipçilere
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  v_json := public.live_create_user_session('Hikâye testi', NULL);
  v_s := (v_json ->> 'id')::uuid;
  v_json := public.start_live_session(v_s);
  EXECUTE 'RESET ROLE';
  v_notified := (v_json ->> 'notified')::int;
  SELECT count(*) INTO v_n FROM public.notifications WHERE type = 'live_started' AND entity_id = v_s::text;
  IF v_notified IS NULL OR v_notified < 1 OR v_n <> v_notified THEN
    RAISE EXCEPTION '[1] sayı: bildirilen % / yazılan %', v_notified, v_n;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_fan AND type = 'live_started' AND entity_id = v_s::text) THEN
    RAISE EXCEPTION '[1] takipçiye bildirim yok';
  END IF;
  IF EXISTS (SELECT 1 FROM public.notifications WHERE user_id IN (v_viewer, v_other) AND type = 'live_started' AND entity_id = v_s::text) THEN
    RAISE EXCEPTION '[1] takipçi olmayana ya da engellenene bildirim gitti';
  END IF;
  IF EXISTS (SELECT 1 FROM public.notifications n
              WHERE n.type = 'live_started' AND n.entity_id = v_s::text
                AND NOT EXISTS (SELECT 1 FROM public.follows f WHERE f.follower_id = n.user_id AND f.following_id = v_host)) THEN
    RAISE EXCEPTION '[1] takipçi olmayan bir alıcı var';
  END IF;
  v_checks := v_checks + 1;

  -- [2] yayın biter bitmez ana sayfa kartında "son yayın"
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  PERFORM public.end_live_session(v_s);
  EXECUTE 'RESET ROLE';
  UPDATE public.live_sessions
     SET started_at = now() - interval '31 minutes', ended_at = now() - interval '1 minute'
   WHERE id = v_s;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_last := public.live_home_card() -> 'last';
  EXECUTE 'RESET ROLE';
  IF v_last IS NULL OR jsonb_typeof(v_last) <> 'object' OR (v_last ->> 'id')::uuid <> v_s THEN
    RAISE EXCEPTION '[2] biten yayın kartta yok: %', v_last;
  END IF;
  v_checks := v_checks + 1;

  -- [3] 23 saat sonra hâlâ görünür (daha yeni biten başka yayın yoksa o)
  UPDATE public.live_sessions
     SET started_at = now() - interval '23 hours 30 minutes', ended_at = now() - interval '23 hours'
   WHERE id = v_s;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_last := public.live_home_card() -> 'last';
  EXECUTE 'RESET ROLE';
  IF v_last IS NULL OR jsonb_typeof(v_last) <> 'object'
     OR NOT ((v_last ->> 'id')::uuid = v_s OR (v_last ->> 'ended_at')::timestamptz > now() - interval '23 hours') THEN
    RAISE EXCEPTION '[3] 23 saatlik yayın: %', v_last;
  END IF;
  v_checks := v_checks + 1;

  -- [4] 24 saati geçince ana sayfadan kaybolur
  UPDATE public.live_sessions
     SET started_at = now() - interval '25 hours 30 minutes', ended_at = now() - interval '25 hours'
   WHERE id = v_s;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_last := public.live_home_card() -> 'last';
  EXECUTE 'RESET ROLE';
  IF v_last IS NOT NULL AND jsonb_typeof(v_last) = 'object'
     AND ((v_last ->> 'id')::uuid = v_s OR (v_last ->> 'ended_at')::timestamptz <= now() - interval '24 hours') THEN
    RAISE EXCEPTION '[4] 24 saati geçen yayın kartta: %', v_last;
  END IF;
  v_checks := v_checks + 1;

  -- [5] Canlı Yayınlar › Geçmiş etkilenmez (ayardaki 30 gün)
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_json := public.live_history(50, 0, NULL);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_s) THEN
    RAISE EXCEPTION '[5] geçmiş sekmesinden düştü: %', v_json -> 'total';
  END IF;
  v_checks := v_checks + 1;

  -- [6] Yayınlarım: süre sınırı yok (40 gün önce biten herkese açık geçmişte yok, sahibinde var)
  UPDATE public.live_sessions
     SET started_at = now() - interval '40 days 30 minutes', ended_at = now() - interval '40 days'
   WHERE id = v_s;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_json := public.live_history(50, 0, NULL);
  EXECUTE 'RESET ROLE';
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_s) THEN
    RAISE EXCEPTION '[6] 40 günlük yayın herkese açık geçmişte';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  v_json := public.live_my_history(20, 0);
  EXECUTE 'RESET ROLE';
  SELECT e INTO v_last FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_s;
  IF v_last IS NULL OR v_last ->> 'kind' <> 'user' OR (v_last ->> 'duration_seconds')::int <> 1800
     OR v_last -> 'message_count' IS NULL OR (v_json ->> 'total')::int <> 1 THEN
    RAISE EXCEPTION '[6] yayınlarım: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [7] sayfalama: en yeni önce, sayfalar örtüşmez
  INSERT INTO public.live_sessions (host_user_id, shop_id, title, channel_name, status, started_at, ended_at, ended_reason)
  VALUES (v_host, NULL, 'İkinci yayın', 'cz_' || md5(random()::text), 'ended',
          now() - interval '2 days 1 hour', now() - interval '2 days', 'host')
  RETURNING id INTO v_s2;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  v_json := public.live_my_history(1, 0);
  v_last := public.live_my_history(1, 1);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'total')::int <> 2 OR (v_json -> 'rows' -> 0 ->> 'id')::uuid <> v_s2
     OR (v_last -> 'rows' -> 0 ->> 'id')::uuid <> v_s OR jsonb_array_length(v_last -> 'rows') <> 1 THEN
    RAISE EXCEPTION '[7] sayfalar: % / %', v_json, v_last;
  END IF;
  v_checks := v_checks + 1;

  -- [8] başkasının yayınları görünmez
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_viewer, 'role', 'authenticated')::text, true);
  v_json := public.live_my_history(50, 0);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'total')::int <> 0 OR jsonb_array_length(v_json -> 'rows') <> 0 THEN
    RAISE EXCEPTION '[8] başkasının yayınları: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [9] mağaza yayını da yayıncısının (mağaza sahibi) Yayınlarım'ında
  INSERT INTO public.live_sessions (host_user_id, shop_id, title, channel_name, status, started_at, ended_at, ended_reason)
  VALUES (v_owner, v_shop, 'Eski mağaza yayını', 'cz_' || md5(random()::text), 'ended',
          now() - interval '60 days 1 hour', now() - interval '60 days', 'host')
  RETURNING id INTO v_ss;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_json := public.live_my_history(50, 0);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                  WHERE (e ->> 'id')::uuid = v_ss AND e ->> 'kind' = 'shop' AND (e ->> 'shop_id')::uuid = v_shop) THEN
    RAISE EXCEPTION '[9] mağaza yayını sahibinde yok: %', v_json -> 'total';
  END IF;
  v_checks := v_checks + 1;

  -- [10] yetkiler: misafire kapalı; oturumsuz çağrı AUTH_REQUIRED
  IF has_function_privilege('anon', 'public.live_my_history(integer, integer)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.live_my_history(integer, integer)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.live_home_card()', 'EXECUTE') THEN
    RAISE EXCEPTION '[10] yetkiler';
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
    PERFORM public.live_my_history(20, 0);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  EXECUTE 'RESET ROLE';
  IF v_hint IS DISTINCT FROM 'AUTH_REQUIRED' THEN RAISE EXCEPTION '[10] oturumsuz: %', v_hint; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
