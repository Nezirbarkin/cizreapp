-- Görev 3.4 — canlı yayın canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/live_stream_completion_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası: DO bloğu RAISE EXCEPTION ile biter,
-- testin yazdığı her şey (yayınlar, mesajlar, sabitlemeler) geri alınır.
DO $test$
DECLARE
  v_shop1 uuid; v_o1 uuid;           -- aktif + onaylı mağaza, 2 satışta ürün
  v_shop2 uuid; v_o2 uuid;           -- başka aktif mağaza
  v_shop_off uuid; v_o_off uuid;     -- pasif mağaza
  v_p1 uuid; v_p2 uuid; v_p_other uuid;
  v_u1 uuid; v_u2 uuid;
  v_s1 uuid; v_s2 uuid; v_s3 uuid;
  v_json jsonb;
  v_hint text; v_state text; v_msg text;
  v_n integer;
  v_text text;
  v_msg_id uuid;
  v_checks integer := 0;
BEGIN
  SELECT s.id, s.owner_id INTO v_shop1, v_o1
    FROM public.shops s
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false)
     AND (SELECT count(*) FROM public.products p
           WHERE p.shop_id = s.id AND COALESCE(p.is_available, false) AND COALESCE(p.is_active, true)) >= 2
   ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_p1 FROM public.products
   WHERE shop_id = v_shop1 AND COALESCE(is_available, false) AND COALESCE(is_active, true) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_p2 FROM public.products
   WHERE shop_id = v_shop1 AND COALESCE(is_available, false) AND COALESCE(is_active, true) AND id <> v_p1
   ORDER BY created_at LIMIT 1;
  SELECT s.id, s.owner_id INTO v_shop2, v_o2
    FROM public.shops s
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) AND s.owner_id <> v_o1
     AND EXISTS (SELECT 1 FROM public.products p WHERE p.shop_id = s.id)
   ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_p_other FROM public.products WHERE shop_id = v_shop2 ORDER BY created_at LIMIT 1;
  SELECT s.id, s.owner_id INTO v_shop_off, v_o_off
    FROM public.shops s
   WHERE NOT COALESCE(s.is_active, false) AND s.owner_id NOT IN (v_o1, v_o2)
   ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_u1 FROM public.profiles
   WHERE id NOT IN (SELECT owner_id FROM public.shops) AND NULLIF(btrim(username), '') IS NOT NULL
   ORDER BY created_at LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles
   WHERE id NOT IN (SELECT owner_id FROM public.shops) AND id <> v_u1 ORDER BY created_at LIMIT 1;
  IF v_p2 IS NULL OR v_p_other IS NULL OR v_shop_off IS NULL OR v_u2 IS NULL THEN
    RAISE EXCEPTION 'test verisi yok';
  END IF;
  -- Temiz başlangıç (tabloda gerçek yayın yok; olsa da bu mağazalarınkini kaldır)
  DELETE FROM public.live_sessions WHERE shop_id IN (v_shop1, v_shop2, v_shop_off);

  -- [1] yapı: yazmalar yalnız RPC'den; token kararı yalnız service_role; cron işi
  IF has_table_privilege('authenticated', 'public.live_sessions', 'INSERT')
     OR has_table_privilege('authenticated', 'public.live_sessions', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.live_pinned_products', 'INSERT')
     OR has_table_privilege('anon', 'public.live_messages', 'INSERT')
     OR has_table_privilege('authenticated', 'public.live_messages', 'UPDATE') THEN
    RAISE EXCEPTION '[1] doğrudan yazma yetkisi kalmış';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.live_messages', 'INSERT')
     OR NOT has_table_privilege('anon', 'public.live_sessions', 'SELECT') THEN
    RAISE EXCEPTION '[1] gereken yetki kaldırılmış';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
              AND tablename IN ('live_sessions', 'live_pinned_products') AND cmd IN ('INSERT', 'UPDATE', 'DELETE')) THEN
    RAISE EXCEPTION '[1] yayın/sabitleme yazma politikası kalmış';
  END IF;
  IF has_function_privilege('anon', 'public.live_token_grant(uuid, text, uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.live_token_grant(uuid, text, uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.live_token_grant(uuid, text, uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] live_token_grant yetkisi yanlış';
  END IF;
  IF has_function_privilege('anon', 'public.live_create_session(uuid, text, text)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.live_sessions_feed(integer)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.live_session_detail(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] RPC yetkileri yanlış';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'live-reap-stale-sessions' AND schedule = '* * * * *') THEN
    RAISE EXCEPTION '[1] temizlik işi yok';
  END IF;
  v_checks := v_checks + 1;

  -- [2] yayın hazırlama: sahip olmayan, kısa başlık, pasif mağaza reddedilir
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
    PERFORM public.live_create_session(v_shop1, 'Deneme yayını', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_msg = MESSAGE_TEXT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_NOT_SHOP_OWNER' THEN RAISE EXCEPTION '[2] sahip değil: % %', v_hint, v_msg; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
    PERFORM public.live_create_session(v_shop1, '  ab ', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_msg = MESSAGE_TEXT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_TITLE_INVALID' THEN RAISE EXCEPTION '[2] başlık: % %', v_hint, v_msg; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o_off, 'role', 'authenticated')::text, true);
    PERFORM public.live_create_session(v_shop_off, 'Pasif mağaza yayını', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_msg = MESSAGE_TEXT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_SHOP_INACTIVE' THEN RAISE EXCEPTION '[2] pasif: % %', v_hint, v_msg; END IF;

  -- geçerli hazırlık; ikinci çağrı aynı kaydı (başlığı güncelleyerek) döner
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.live_create_session(v_shop1, '  Yeni   sezon ', '  açıklama ');
  v_s1 := (v_json ->> 'id')::uuid;
  IF v_json ->> 'status' <> 'scheduled' OR v_json ->> 'title' <> 'Yeni sezon'
     OR v_json ->> 'description' <> 'açıklama' OR (v_json ->> 'resumed')::boolean
     OR v_json ->> 'channel_name' !~ '^cz_[0-9a-f]{32}$' OR v_json ->> 'shop_name' IS NULL
     OR (v_json ->> 'is_live')::boolean THEN
    RAISE EXCEPTION '[2] hazırlık: %', v_json;
  END IF;
  v_json := public.live_create_session(v_shop1, 'Kış koleksiyonu', NULL);
  IF (v_json ->> 'id')::uuid <> v_s1 OR v_json ->> 'title' <> 'Kış koleksiyonu' THEN
    RAISE EXCEPTION '[2] hazırlık yeniden kullanılmadı: %', v_json;
  END IF;
  EXECUTE 'RESET ROLE';
  v_checks := v_checks + 1;

  -- [3] Agora anahtarı yetki kararı
  v_json := public.live_token_grant(v_s1, 'viewer', v_u1);
  IF v_json ->> 'error' <> 'NOT_LIVE' THEN RAISE EXCEPTION '[3] başlamamış yayına izleyici: %', v_json; END IF;
  v_json := public.live_token_grant(v_s1, 'host', v_o1);
  IF NOT (v_json ->> 'ok')::boolean OR (v_json ->> 'host_uid')::int <> 1
     OR v_json ->> 'channel' <> (SELECT channel_name FROM public.live_sessions WHERE id = v_s1) THEN
    RAISE EXCEPTION '[3] satıcı anahtarı: %', v_json;
  END IF;
  IF public.live_token_grant(v_s1, 'host', v_u1) ->> 'error' <> 'FORBIDDEN'
     OR public.live_token_grant(v_s1, 'host', NULL) ->> 'error' <> 'AUTH_REQUIRED'
     OR public.live_token_grant(v_s1, 'admin', v_o1) ->> 'error' <> 'BAD_ROLE'
     OR public.live_token_grant(gen_random_uuid(), 'viewer', NULL) ->> 'error' <> 'NOT_FOUND' THEN
    RAISE EXCEPTION '[3] ret kodları';
  END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
    PERFORM public.live_token_grant(v_s1, 'host', v_o1);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[3] istemci karar fonksiyonunu çağırabildi: %', v_state; END IF;
  v_checks := v_checks + 1;

  -- [4] yayını başlat: yalnız sahibi; canlı listede görünür (misafir de görür)
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
    PERFORM public.start_live_session(v_s1);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_NOT_HOST' THEN RAISE EXCEPTION '[4] başkası başlattı: %', v_hint; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.start_live_session(v_s1);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'live' OR NOT (v_json ->> 'is_live')::boolean OR v_json ->> 'started_at' IS NULL THEN
    RAISE EXCEPTION '[4] başlamadı: %', v_json;
  END IF;
  IF NOT (public.live_token_grant(v_s1, 'viewer', NULL) ->> 'ok')::boolean THEN
    RAISE EXCEPTION '[4] misafir izleyici anahtarı alamadı';
  END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_json := public.live_sessions_feed(30);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'live') e WHERE (e ->> 'id')::uuid = v_s1
                  AND e ->> 'shop_name' IS NOT NULL) THEN
    RAISE EXCEPTION '[4] keşfet listesinde yok: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [5] mesajlar: satıcı bayrağı/ad sunucuda; boş/uzun/hızlı mesaj ve misafir reddedilir
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
  INSERT INTO public.live_messages (session_id, user_id, message, is_host, author_name)
  VALUES (v_s1, v_u1, E'  merhaba \n  dünya  ', true, 'Sahte Satıcı')
  RETURNING id INTO v_msg_id;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  INSERT INTO public.live_messages (session_id, user_id, message, is_host) VALUES (v_s1, v_o1, 'Hoş geldiniz', false);
  EXECUTE 'RESET ROLE';
  SELECT message || '|' || is_host::text || '|' || author_name INTO v_text FROM public.live_messages WHERE id = v_msg_id;
  IF v_text <> 'merhaba dünya|false|' || (SELECT btrim(username) FROM public.profiles WHERE id = v_u1) THEN
    RAISE EXCEPTION '[5] izleyici mesajı: %', v_text;
  END IF;
  SELECT is_host::text || '|' || author_name INTO v_text FROM public.live_messages
   WHERE session_id = v_s1 AND user_id = v_o1;
  IF v_text <> 'true|' || (SELECT name FROM public.shops WHERE id = v_shop1) THEN
    RAISE EXCEPTION '[5] satıcı mesajı: %', v_text;
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u2, 'role', 'authenticated')::text, true);
    INSERT INTO public.live_messages (session_id, user_id, message) VALUES (v_s1, v_u2, '   ');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_MESSAGE_EMPTY' THEN RAISE EXCEPTION '[5] boş: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u2, 'role', 'authenticated')::text, true);
    INSERT INTO public.live_messages (session_id, user_id, message) VALUES (v_s1, v_u2, repeat('a', 301));
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_MESSAGE_TOO_LONG' THEN RAISE EXCEPTION '[5] uzun: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u2, 'role', 'authenticated')::text, true);
    FOR v_n IN 1..6 LOOP
      INSERT INTO public.live_messages (session_id, user_id, message) VALUES (v_s1, v_u2, 'mesaj ' || v_n);
    END LOOP;
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_MESSAGE_RATE' THEN RAISE EXCEPTION '[5] hız sınırı: %', v_hint; END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    INSERT INTO public.live_messages (session_id, user_id, message) VALUES (v_s1, v_u2, 'misafir');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[5] misafir mesaj yazdı: %', v_state; END IF;
  -- başka kullanıcı adına yazılamaz
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u2, 'role', 'authenticated')::text, true);
    INSERT INTO public.live_messages (session_id, user_id, message) VALUES (v_s1, v_u1, 'taklit');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[5] başkası adına yazdı: %', v_state; END IF;
  v_checks := v_checks + 1;

  -- [6] ürün sabitleme: yalnız kendi mağazasının satıştaki ürünü; tek güncel sabit
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
    PERFORM public.live_pin_product(v_s1, v_p_other);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_PRODUCT_INVALID' THEN RAISE EXCEPTION '[6] başka mağazanın ürünü: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
    PERFORM public.live_pin_product(v_s1, v_p1);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_NOT_HOST' THEN RAISE EXCEPTION '[6] izleyici sabitledi: %', v_hint; END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
    INSERT INTO public.live_pinned_products (session_id, product_id, pinned_by) VALUES (v_s1, v_p1, v_o1);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[6] doğrudan sabitleme: %', v_state; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.live_pin_product(v_s1, v_p1);
  IF (v_json -> 'pinned_product' ->> 'id')::uuid <> v_p1
     OR (v_json -> 'pinned_product' ->> 'effective_price') IS NULL THEN
    RAISE EXCEPTION '[6] sabit ürün: %', v_json;
  END IF;
  v_json := public.live_pin_product(v_s1, v_p2);
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_n FROM public.live_pinned_products WHERE session_id = v_s1 AND is_current;
  IF v_n <> 1 OR (SELECT product_id FROM public.live_pinned_products WHERE session_id = v_s1 AND is_current) <> v_p2
     OR (SELECT count(*) FROM public.live_pinned_products WHERE session_id = v_s1) <> 2 THEN
    RAISE EXCEPTION '[6] tek güncel sabit yok (%)', v_n;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.live_unpin_product(v_s1);
  EXECUTE 'RESET ROLE';
  IF v_json -> 'pinned_product' <> 'null'::jsonb
     OR EXISTS (SELECT 1 FROM public.live_pinned_products WHERE session_id = v_s1 AND is_current) THEN
    RAISE EXCEPTION '[6] kaldırılmadı: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [7] canlılık sinyali: izleyici sayısı ve en yüksek sayı; doğrudan UPDATE yok
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.live_session_heartbeat(v_s1, 7);
  IF v_json ->> 'status' <> 'live' OR (v_json ->> 'viewer_count')::int <> 7 OR (v_json ->> 'peak_viewer_count')::int <> 7 THEN
    RAISE EXCEPTION '[7] sinyal 7: %', v_json;
  END IF;
  v_json := public.live_session_heartbeat(v_s1, 3);
  IF (v_json ->> 'viewer_count')::int <> 3 OR (v_json ->> 'peak_viewer_count')::int <> 7 THEN
    RAISE EXCEPTION '[7] sinyal 3: %', v_json;
  END IF;
  v_json := public.live_session_heartbeat(v_s1, -5);
  IF (v_json ->> 'viewer_count')::int <> 0 THEN RAISE EXCEPTION '[7] eksi sayı: %', v_json; END IF;
  EXECUTE 'RESET ROLE';
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
    UPDATE public.live_sessions SET peak_viewer_count = 99999 WHERE id = v_s1;
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[7] satıcı sayacı elle yazdı: %', v_state; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
    PERFORM public.live_session_heartbeat(v_s1, 50);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_NOT_HOST' THEN RAISE EXCEPTION '[7] izleyici sinyal verdi: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [8] moderasyon: satıcı izleyicinin mesajını siler; izleyici satıcınınkini silemez
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
  DELETE FROM public.live_messages WHERE session_id = v_s1 AND user_id = v_o1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  DELETE FROM public.live_messages WHERE id = v_msg_id;
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM public.live_messages WHERE session_id = v_s1 AND user_id = v_o1) THEN
    RAISE EXCEPTION '[8] izleyici satıcının mesajını sildi';
  END IF;
  IF EXISTS (SELECT 1 FROM public.live_messages WHERE id = v_msg_id) THEN
    RAISE EXCEPTION '[8] satıcı izleyicinin mesajını silemedi';
  END IF;
  v_checks := v_checks + 1;

  -- [9] bayat yayın: sinyal 3 dk önce kesilmiş → temizlik 'timeout' ile kapatır
  UPDATE public.live_sessions SET pinned_product_id = v_p1,
         last_heartbeat_at = now() - interval '3 minutes'
   WHERE id = v_s1;
  v_n := private.live_reap_stale_sessions();
  SELECT jsonb_build_object('status', status, 'reason', ended_reason, 'ended', ended_at, 'hb', last_heartbeat_at,
                            'viewers', viewer_count, 'pin', pinned_product_id)
    INTO v_json FROM public.live_sessions WHERE id = v_s1;
  IF v_n < 1 OR v_json ->> 'status' <> 'ended' OR v_json ->> 'reason' <> 'timeout'
     OR v_json ->> 'ended' <> v_json ->> 'hb' OR (v_json ->> 'viewers')::int <> 0 OR v_json ->> 'pin' IS NOT NULL THEN
    RAISE EXCEPTION '[9] temizlik: % (%)', v_json, v_n;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.live_session_heartbeat(v_s1, 4);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'ended' OR v_json ->> 'ended_reason' <> 'timeout' THEN
    RAISE EXCEPTION '[9] kapanan yayına sinyal: %', v_json;
  END IF;
  IF public.live_token_grant(v_s1, 'viewer', v_u1) ->> 'error' <> 'ENDED'
     OR public.live_token_grant(v_s1, 'host', v_o1) ->> 'error' <> 'ENDED' THEN
    RAISE EXCEPTION '[9] biten yayına anahtar';
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u1, 'role', 'authenticated')::text, true);
    INSERT INTO public.live_messages (session_id, user_id, message) VALUES (v_s1, v_u1, 'geç kaldım');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_NOT_LIVE' THEN RAISE EXCEPTION '[9] biten yayına mesaj: %', v_hint; END IF;
  v_json := public.live_sessions_feed(30);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'live') e WHERE (e ->> 'id')::uuid = v_s1)
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'recent') e WHERE (e ->> 'id')::uuid = v_s1) THEN
    RAISE EXCEPTION '[9] keşfet: biten yayın yanlış listede';
  END IF;
  v_checks := v_checks + 1;

  -- [10] yeniden açma, sürdürme, bitirme özeti, hiç başlamayanın silinmesi
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.live_create_session(v_shop1, 'İkinci yayın', NULL);
  v_s2 := (v_json ->> 'id')::uuid;
  IF v_s2 = v_s1 OR v_json ->> 'status' <> 'scheduled' THEN RAISE EXCEPTION '[10] yeni yayın: %', v_json; END IF;
  PERFORM public.start_live_session(v_s2);
  v_json := public.live_create_session(v_shop1, 'Üçüncü', NULL);
  IF (v_json ->> 'id')::uuid <> v_s2 OR NOT (v_json ->> 'resumed')::boolean THEN
    RAISE EXCEPTION '[10] taze canlı yayın sürdürülmedi: %', v_json;
  END IF;
  EXECUTE 'RESET ROLE';
  UPDATE public.live_sessions SET last_heartbeat_at = now() - interval '5 minutes' WHERE id = v_s2;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.live_create_session(v_shop1, 'Dördüncü', NULL);
  v_s3 := (v_json ->> 'id')::uuid;
  EXECUTE 'RESET ROLE';
  IF v_s3 = v_s2 OR (SELECT ended_reason FROM public.live_sessions WHERE id = v_s2) <> 'timeout' THEN
    RAISE EXCEPTION '[10] bayat yayın kapatılıp yenisi açılmadı: %', v_json;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.end_live_session(v_s3);   -- hiç başlamadı → silinir
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'discarded' OR EXISTS (SELECT 1 FROM public.live_sessions WHERE id = v_s3) THEN
    RAISE EXCEPTION '[10] başlamayan yayın silinmedi: %', v_json;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.live_create_session(v_shop1, 'Beşinci yayın', NULL);
  v_s3 := (v_json ->> 'id')::uuid;
  PERFORM public.start_live_session(v_s3);
  PERFORM public.live_session_heartbeat(v_s3, 12);
  INSERT INTO public.live_messages (session_id, user_id, message) VALUES (v_s3, v_o1, 'Başlıyoruz');
  v_json := public.end_live_session(v_s3);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'ended' OR v_json ->> 'ended_reason' <> 'host'
     OR (v_json ->> 'peak_viewer_count')::int <> 12 OR (v_json ->> 'message_count')::int <> 1
     OR (v_json ->> 'duration_seconds')::int < 0 THEN
    RAISE EXCEPTION '[10] bitirme özeti: %', v_json;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o1, 'role', 'authenticated')::text, true);
  v_json := public.end_live_session(v_s3);    -- ikinci kez: değişmez
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'ended_reason' <> 'host' THEN RAISE EXCEPTION '[10] ikinci bitirme: %', v_json; END IF;
  v_checks := v_checks + 1;

  -- [11] detay (misafir); bilinmeyen yayın null; başka mağazanın hazırlığı ayrı
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_json := public.live_session_detail(v_s3);
  IF v_json ->> 'status' <> 'ended' OR v_json ->> 'shop_logo_url' IS DISTINCT FROM (SELECT logo_url FROM public.shops WHERE id = v_shop1) THEN
    RAISE EXCEPTION '[11] detay: %', v_json;
  END IF;
  IF public.live_session_detail(gen_random_uuid()) IS NOT NULL THEN RAISE EXCEPTION '[11] bilinmeyen yayın'; END IF;
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o2, 'role', 'authenticated')::text, true);
  v_json := public.live_create_session(v_shop2, 'Diğer mağaza', NULL);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'shop_id')::uuid <> v_shop2 OR (v_json ->> 'id')::uuid IN (v_s1, v_s2, v_s3) THEN
    RAISE EXCEPTION '[11] mağazalar karıştı: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
