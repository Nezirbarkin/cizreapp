-- Kullanıcı (mağazasız) canlı yayını canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/user_live_streams_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_host uuid; v_host_name text; v_viewer uuid; v_fan uuid; v_admin uuid; v_other uuid;
  v_shop uuid; v_owner uuid; v_product uuid;
  v_s uuid; v_s2 uuid; v_ss uuid;
  v_json jsonb;
  v_hint text;
  v_n integer;
  v_row public.live_sessions%ROWTYPE;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT s.id, s.owner_id INTO v_shop, v_owner
    FROM public.shops s
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) AND s.owner_id IS NOT NULL
   ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_product FROM public.products WHERE shop_id = v_shop LIMIT 1;

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
  IF v_admin IS NULL OR v_shop IS NULL OR v_other IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;
  SELECT username INTO v_host_name FROM public.profiles WHERE id = v_host;

  -- Temiz başlangıç
  DELETE FROM public.live_sessions WHERE host_user_id IN (v_host, v_other) OR (shop_id = v_shop AND status <> 'ended');
  DELETE FROM public.user_live_permissions WHERE user_id IN (v_host, v_other);
  DELETE FROM public.live_notify_log WHERE host_user_id = v_host;
  DELETE FROM public.follows WHERE following_id = v_host AND follower_id IN (v_viewer, v_fan, v_other);
  DELETE FROM public.blocked_users WHERE (blocker_id = v_host AND blocked_id IN (v_viewer, v_fan, v_other))
                                      OR (blocked_id = v_host AND blocker_id IN (v_viewer, v_fan, v_other));
  DELETE FROM public.notification_preferences WHERE user_id = v_fan;
  UPDATE public.profiles SET profile_is_public = true WHERE id = v_host;
  INSERT INTO public.follows (follower_id, following_id) VALUES (v_fan, v_host);
  UPDATE public.app_settings SET value = '"true"'::jsonb WHERE key IN ('live_stream_enabled', 'live_notify_enabled', 'live_notify_user_followers');
  UPDATE public.app_settings SET value = '"open"'::jsonb WHERE key = 'live_user_streams';

  -- [1] erişim bilgisi: açık mod → ok
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  v_json := public.live_my_stream_access();
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'access' <> 'ok' OR v_json ->> 'mode' <> 'open' THEN RAISE EXCEPTION '[1] erişim: %', v_json; END IF;
  v_checks := v_checks + 1;

  -- [2] kullanıcı yayın hazırlar ve başlatır; tür/yayıncı kimliği; takipçiye bildirim
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  v_json := public.live_create_user_session('  Akşam   sohbeti ', NULL);
  v_s := (v_json ->> 'id')::uuid;
  IF v_json ->> 'kind' <> 'user' OR v_json ->> 'shop_id' IS NOT NULL OR v_json ->> 'title' <> 'Akşam sohbeti'
     OR v_json ->> 'host_display_name' <> v_host_name OR v_json ->> 'status' <> 'scheduled' THEN
    RAISE EXCEPTION '[2] hazırlık: %', v_json;
  END IF;
  v_json := public.start_live_session(v_s);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'live' OR (v_json ->> 'notified')::int < 1 THEN RAISE EXCEPTION '[2] başlatma: %', v_json; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications
                  WHERE user_id = v_fan AND type = 'live_started' AND entity_id = v_s::text
                    AND title LIKE '%' || v_host_name || '%' AND actor_id = v_host) THEN
    RAISE EXCEPTION '[2] takipçiye bildirim yok';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.live_notify_log WHERE session_id = v_s AND shop_id IS NULL AND host_user_id = v_host) THEN
    RAISE EXCEPTION '[2] bildirim günlüğü';
  END IF;
  v_checks := v_checks + 1;

  -- [3] tekrar hazırla = süren yayın sürdürülür; ürün sabitlenemez
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  v_json := public.live_create_user_session('Başka', NULL);
  IF (v_json ->> 'id')::uuid <> v_s OR (v_json ->> 'resumed')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION '[3] sürdürme: %', v_json;
  END IF;
  v_hint := NULL;
  BEGIN
    PERFORM public.live_pin_product(v_s, v_product);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  EXECUTE 'RESET ROLE';
  IF v_hint IS DISTINCT FROM 'LIVE_PRODUCT_INVALID' THEN RAISE EXCEPTION '[3] ürün sabitleme: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [4] herkese açık hesap: misafir ve başkası akışta görür, anahtar alır; sohbette yayıncı kendi adıyla
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_json := public.live_sessions_feed(100);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'live') e WHERE (e ->> 'id')::uuid = v_s)
     OR v_json ->> 'my_access' <> 'AUTH_REQUIRED' THEN
    RAISE EXCEPTION '[4] misafir akışı: %', v_json;
  END IF;
  IF (public.live_token_grant(v_s, 'viewer', NULL) ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION '[4] misafir anahtarı'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  INSERT INTO public.live_messages (session_id, user_id, message) VALUES (v_s, v_host, 'Merhaba');
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM public.live_messages WHERE session_id = v_s AND is_host AND author_name = v_host_name) THEN
    RAISE EXCEPTION '[4] yayıncı mesajı';
  END IF;
  v_checks := v_checks + 1;

  -- [5] gizli hesap: takipçi olmayan/misafir göremez (akış, ayrıntı, satır, anahtar, mesaj); takipçi görür
  UPDATE public.profiles SET profile_is_public = false WHERE id = v_host;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_viewer, 'role', 'authenticated')::text, true);
  v_json := public.live_sessions_feed(100);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'live') e WHERE (e ->> 'id')::uuid = v_s) THEN
    RAISE EXCEPTION '[5] gizli yayın akışta';
  END IF;
  IF public.live_session_detail(v_s) IS NOT NULL THEN RAISE EXCEPTION '[5] ayrıntı sızdı'; END IF;
  SELECT count(*) INTO v_n FROM public.live_sessions WHERE id = v_s;
  IF v_n <> 0 THEN RAISE EXCEPTION '[5] satır RLS''ten sızdı'; END IF;
  SELECT count(*) INTO v_n FROM public.live_messages WHERE session_id = v_s;
  IF v_n <> 0 THEN RAISE EXCEPTION '[5] mesajlar sızdı'; END IF;
  v_hint := NULL;
  BEGIN
    INSERT INTO public.live_messages (session_id, user_id, message) VALUES (v_s, v_viewer, 'selam');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  EXECUTE 'RESET ROLE';
  IF v_hint IS DISTINCT FROM 'LIVE_NOT_FOUND' THEN RAISE EXCEPTION '[5] yabancı mesaj yazdı: %', v_hint; END IF;
  IF public.live_token_grant(v_s, 'viewer', v_viewer) ->> 'error' <> 'NOT_FOUND'
     OR public.live_token_grant(v_s, 'viewer', NULL) ->> 'error' <> 'NOT_FOUND'
     OR (public.live_token_grant(v_s, 'viewer', v_fan) ->> 'ok')::boolean IS NOT TRUE
     OR (public.live_token_grant(v_s, 'viewer', v_admin) ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION '[5] anahtar gizliliği';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fan, 'role', 'authenticated')::text, true);
  v_json := public.live_sessions_feed(100);
  SELECT count(*) INTO v_n FROM public.live_messages WHERE session_id = v_s;
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'live') e WHERE (e ->> 'id')::uuid = v_s) OR v_n < 1 THEN
    RAISE EXCEPTION '[5] takipçi göremedi: % / %', v_json, v_n;
  END IF;
  v_checks := v_checks + 1;

  -- [6] engel: herkese açık hesapta bile engellenen göremez
  UPDATE public.profiles SET profile_is_public = true WHERE id = v_host;
  INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (v_host, v_viewer);
  IF public.live_token_grant(v_s, 'viewer', v_viewer) ->> 'error' <> 'NOT_FOUND' THEN RAISE EXCEPTION '[6] engelli anahtar aldı'; END IF;
  DELETE FROM public.blocked_users WHERE blocker_id = v_host AND blocked_id = v_viewer;
  v_checks := v_checks + 1;

  -- [7] yönetici listesi kullanıcı yayınını gösterir ve kapatır
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_live_sessions('live', 100, 0);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                  WHERE (e ->> 'id')::uuid = v_s AND e ->> 'kind' = 'user' AND e ->> 'shop_access' = 'ok')
     OR v_json -> 'settings' ->> 'user_mode' <> 'open' OR (v_json -> 'summary' ->> 'user_live_now')::int < 1 THEN
    RAISE EXCEPTION '[7] liste: %', v_json;
  END IF;
  v_json := public.admin_end_live_session(v_s, 'Kural dışı');
  EXECUTE 'RESET ROLE';
  SELECT * INTO v_row FROM public.live_sessions WHERE id = v_s;
  IF v_row.status <> 'ended' OR v_row.ended_reason <> 'admin' THEN RAISE EXCEPTION '[7] kapatma: %', v_row; END IF;
  v_checks := v_checks + 1;

  -- [8] davet modu: izinsiz açamaz; izin verilince açar; izin kalkınca süren yayın kapanır
  UPDATE public.app_settings SET value = '"invite"'::jsonb WHERE key = 'live_user_streams';
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
    PERFORM public.live_create_user_session('Deneme yayını', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  EXECUTE 'RESET ROLE';
  IF v_hint IS DISTINCT FROM 'LIVE_USER_NOT_PERMITTED' THEN RAISE EXCEPTION '[8] davetsiz açtı: %', v_hint; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_user_live_permission(v_other, 'granted', NULL);
  IF v_json ->> 'effective' <> 'ok' THEN RAISE EXCEPTION '[8] izin: %', v_json; END IF;
  v_json := public.admin_live_users(NULL, 'granted', 50, 0);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'user_id')::uuid = v_other) THEN
    RAISE EXCEPTION '[8] kullanıcı listesi: %', v_json;
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  v_s2 := (public.live_create_user_session('Deneme yayını', NULL) ->> 'id')::uuid;
  PERFORM public.start_live_session(v_s2);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_user_live_permission(v_other, 'revoked', 'Şikayet');
  EXECUTE 'RESET ROLE';
  SELECT * INTO v_row FROM public.live_sessions WHERE id = v_s2;
  IF (v_json ->> 'closed')::int <> 1 OR v_row.status <> 'ended' OR v_json ->> 'effective' <> 'LIVE_USER_REVOKED' THEN
    RAISE EXCEPTION '[8] iptal: % / %', v_json, v_row.status;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_other AND type = 'admin_notification'
                    AND content LIKE '%Şikayet%') THEN
    RAISE EXCEPTION '[8] iptal bildirimi yok';
  END IF;
  v_checks := v_checks + 1;

  -- [9] kapalı mod: kimse açamaz; yönetici olmayan modu değiştiremez
  UPDATE public.app_settings SET value = '"off"'::jsonb WHERE key = 'live_user_streams';
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
    PERFORM public.live_create_user_session('Deneme yayını', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  EXECUTE 'RESET ROLE';
  IF v_hint IS DISTINCT FROM 'LIVE_USERS_OFF' THEN RAISE EXCEPTION '[9] kapalıyken açtı: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_user_live_mode('open', false);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = RETURNED_SQLSTATE;
  END;
  EXECUTE 'RESET ROLE';
  IF v_hint IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[9] kullanıcı modu değiştirdi: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [10] mağaza yayını eskisi gibi: hazırla, başlat, akışta mağaza adıyla
  UPDATE public.app_settings SET value = '"open"'::jsonb WHERE key IN ('live_user_streams', 'live_stream_access');
  DELETE FROM public.shop_live_permissions WHERE shop_id = v_shop;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_ss := (public.live_create_session(v_shop, 'Mağaza yayını', NULL) ->> 'id')::uuid;
  v_json := public.start_live_session(v_ss);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'live' OR v_json ->> 'kind' <> 'shop' OR v_json ->> 'shop_name' IS NULL
     OR v_json ->> 'host_display_name' IS NOT NULL THEN
    RAISE EXCEPTION '[10] mağaza yayını: %', v_json;
  END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SELECT count(*) INTO v_n FROM public.live_sessions WHERE id = v_ss;
  EXECUTE 'RESET ROLE';
  IF v_n <> 1 THEN RAISE EXCEPTION '[10] mağaza satırı misafire kapandı'; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED %/10', v_checks;
END;
$test$;
