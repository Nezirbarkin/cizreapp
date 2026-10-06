-- Canlı yayın bildirimi, abonelik, geçmiş, ana sayfa kartı ve yönetici ayarları
-- canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/live_notifications_history_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
-- Son kontrol notifications tablosuna geçici tetikleyici ekler: tablo test
-- süresince (birkaç saniye) yeni satır yazımını bekletir.
DO $test$
DECLARE
  v_shop uuid; v_shop_name text; v_owner uuid; v_product uuid; v_admin uuid; v_bot uuid;
  v_u uuid[];
  v_s1 uuid; v_s2 uuid; v_s3 uuid; v_s4 uuid; v_s5 uuid; v_s6 uuid; v_s7 uuid;
  v_json jsonb; v_json2 jsonb;
  v_ids1 uuid[]; v_ids2 uuid[];
  v_hint text; v_state text;
  v_n integer; v_count integer;
  v_checks integer := 0;
BEGIN
  SELECT s.id, s.name, s.owner_id INTO v_shop, v_shop_name, v_owner
    FROM public.shops s
    JOIN public.profiles o ON o.id = s.owner_id
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false)
     AND o.role::text <> 'admin' AND NOT COALESCE(o.is_bot, false) AND o.status::text = 'active'
     AND EXISTS (SELECT 1 FROM public.products p
                  WHERE p.shop_id = s.id AND COALESCE(p.is_available, false) AND COALESCE(p.is_active, true))
   ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_product FROM public.products
   WHERE shop_id = v_shop AND COALESCE(is_available, false) AND COALESCE(is_active, true)
   ORDER BY id LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_bot FROM public.profiles WHERE is_bot ORDER BY created_at LIMIT 1;
  SELECT array_agg(x.id ORDER BY x.id) INTO v_u FROM (
    SELECT p.id FROM public.profiles p
     WHERE p.id <> v_owner AND p.id <> v_admin AND NOT COALESCE(p.is_bot, false) AND p.status::text = 'active'
     ORDER BY p.created_at DESC LIMIT 6) x;
  IF v_shop IS NULL OR v_product IS NULL OR v_admin IS NULL OR v_bot IS NULL OR cardinality(v_u) < 6 THEN
    RAISE EXCEPTION 'test verisi yok';
  END IF;

  -- Temiz başlangıç (hepsi geri alınır)
  DELETE FROM public.live_sessions WHERE shop_id = v_shop AND status IN ('scheduled', 'live');
  DELETE FROM public.shop_live_permissions WHERE shop_id = v_shop;
  DELETE FROM public.live_subscriptions WHERE shop_id = v_shop;
  DELETE FROM public.live_notify_log WHERE shop_id = v_shop;
  UPDATE public.app_settings SET value = '"true"'::jsonb
   WHERE key IN ('live_stream_enabled', 'live_notify_enabled', 'live_notify_followers',
                 'live_notify_product_fans', 'live_home_card_enabled');
  UPDATE public.app_settings SET value = '"open"'::jsonb WHERE key = 'live_stream_access';
  UPDATE public.app_settings SET value = '"false"'::jsonb WHERE key = 'live_notify_customers';
  UPDATE public.app_settings SET value = '"3"'::jsonb WHERE key = 'live_notify_cooldown_hours';
  UPDATE public.app_settings SET value = '"2000"'::jsonb WHERE key = 'live_notify_max_recipients';
  UPDATE public.app_settings SET value = '"30"'::jsonb WHERE key = 'live_history_days';
  DELETE FROM public.blocked_users
   WHERE (blocker_id = ANY (v_u) AND blocked_id = v_owner) OR (blocker_id = v_owner AND blocked_id = ANY (v_u));
  DELETE FROM public.follows WHERE follower_id = ANY (v_u) AND following_id = v_owner;
  DELETE FROM public.product_favorites pf USING public.products p
   WHERE pf.product_id = p.id AND p.shop_id = v_shop AND pf.user_id = ANY (v_u);
  INSERT INTO public.notification_preferences (user_id, live_streams_enabled)
  SELECT unnest(v_u), true
  ON CONFLICT (user_id) DO UPDATE SET live_streams_enabled = true;

  -- [1] abonelik: aç (iki kez → tek satır), durum okuma; başkası abone görünmez
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u[1], 'role', 'authenticated')::text, true);
  PERFORM public.live_set_subscription(v_shop, true);
  v_json := public.live_set_subscription(v_shop, true);
  v_json2 := public.live_shop_subscription(v_shop);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u[2], 'role', 'authenticated')::text, true);
  v_count := (public.live_shop_subscription(v_shop) ->> 'subscribed')::boolean::int;
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'subscribed')::boolean IS NOT TRUE OR (v_json ->> 'subscribers')::int <> 1
     OR (v_json2 ->> 'subscribed')::boolean IS NOT TRUE OR v_count <> 0 THEN
    RAISE EXCEPTION '[1] abonelik: % / % / %', v_json, v_json2, v_count;
  END IF;
  v_checks := v_checks + 1;

  -- [2] tablo yalnız kendi satırını gösterir, doğrudan yazılamaz; misafir abone
  --     olamaz; olmayan mağaza reddedilir; kapatma satırı siler
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u[2], 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_count FROM public.live_subscriptions;
  EXECUTE 'RESET ROLE';
  IF v_count <> 0 THEN RAISE EXCEPTION '[2] başkasının aboneliği görünüyor: %', v_count; END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u[2], 'role', 'authenticated')::text, true);
    INSERT INTO public.live_subscriptions (user_id, shop_id) VALUES (v_u[2], v_shop);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[2] doğrudan yazdı: %', v_state; END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    PERFORM public.live_set_subscription(v_shop, true);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[2] misafir abone oldu: %', v_state; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u[2], 'role', 'authenticated')::text, true);
    PERFORM public.live_set_subscription(gen_random_uuid(), true);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_SHOP_NOT_FOUND' THEN RAISE EXCEPTION '[2] olmayan mağaza: %', v_hint; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u[2], 'role', 'authenticated')::text, true);
  PERFORM public.live_set_subscription(v_shop, true);
  v_json := public.live_set_subscription(v_shop, false);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'subscribed')::boolean OR (v_json ->> 'subscribers')::int <> 1
     OR EXISTS (SELECT 1 FROM public.live_subscriptions WHERE user_id = v_u[2]) THEN
    RAISE EXCEPTION '[2] abonelikten çıkma: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- Kitle: u1 abone; u2 takipçi; u3 ürün favorileyen; u4 abone ama tercihi
  -- kapalı; u5 abone ama satıcı onu engellemiş; u6 hem abone hem takipçi hem
  -- favorileyen; bot abone.
  INSERT INTO public.live_subscriptions (user_id, shop_id)
  VALUES (v_u[4], v_shop), (v_u[5], v_shop), (v_u[6], v_shop), (v_bot, v_shop);
  INSERT INTO public.follows (follower_id, following_id) VALUES (v_u[2], v_owner), (v_u[6], v_owner);
  INSERT INTO public.product_favorites (user_id, product_id) VALUES (v_u[3], v_product), (v_u[6], v_product);
  UPDATE public.notification_preferences SET live_streams_enabled = false WHERE user_id = v_u[4];
  INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (v_owner, v_u[5]);

  -- [3] yayın başlayınca bildirim: doğru kişilere birer tane, push kuyruğunda,
  --     dönüşte ve günlükte aynı sayı
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s1 := (public.live_create_session(v_shop, 'Bildirim testi', NULL) ->> 'id')::uuid;
  v_json := public.start_live_session(v_s1);
  EXECUTE 'RESET ROLE';
  v_n := (v_json ->> 'notified')::int;
  SELECT count(*) INTO v_count FROM public.notifications WHERE type = 'live_started' AND entity_id = v_s1::text;
  IF v_json ->> 'status' <> 'live' OR v_n IS NULL OR v_n <> v_count OR v_n < 4 THEN
    RAISE EXCEPTION '[3] sayı: % / %', v_json, v_count;
  END IF;
  IF (SELECT count(*) FROM public.notifications n
       WHERE n.type = 'live_started' AND n.entity_id = v_s1::text AND n.entity_type = 'live_session'
         AND n.user_id IN (v_u[1], v_u[2], v_u[3], v_u[6])
         AND n.metadata ->> 'route' = '/live/' || v_s1::text
         AND n.title = format('🔴 %s canlı yayında', v_shop_name)
         AND n.content = 'Bildirim testi' AND n.actor_id = v_owner) <> 4 THEN
    RAISE EXCEPTION '[3] beklenen alıcılar eksik ya da çift';
  END IF;
  IF EXISTS (SELECT 1 FROM public.notifications
              WHERE type = 'live_started' AND entity_id = v_s1::text
                AND user_id IN (v_u[4], v_u[5], v_bot, v_owner)) THEN
    RAISE EXCEPTION '[3] tercihi kapalı / engelli / bot / satıcı bildirim aldı';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notification_outbox ob
                   JOIN public.notifications n ON n.id = ob.notification_id
                  WHERE n.user_id = v_u[1] AND n.type = 'live_started' AND n.entity_id = v_s1::text) THEN
    RAISE EXCEPTION '[3] push kuyruğuna girmedi';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.live_notify_log
                  WHERE session_id = v_s1 AND recipients = v_n AND skipped IS NULL) THEN
    RAISE EXCEPTION '[3] günlük';
  END IF;
  v_checks := v_checks + 1;

  -- [4] canlıyken tekrar çağrı (sinyal) yeniden bildirmez
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_json := public.start_live_session(v_s1);
  EXECUTE 'RESET ROLE';
  IF v_json -> 'notified' <> 'null'::jsonb
     OR (SELECT count(*) FROM public.notifications WHERE type = 'live_started' AND entity_id = v_s1::text) <> v_n THEN
    RAISE EXCEPTION '[4] tekrar bildirdi: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [5] ürün sabitlenip yayın biter: geçmişte ve ayrıntıda öne çıkan ürün,
  --     süre, mesaj sayısı; mağaza süzgeci
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  PERFORM public.live_pin_product(v_s1, v_product);
  PERFORM public.end_live_session(v_s1);
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_json := public.live_history(50, 0, NULL);
  v_json2 := public.live_session_detail(v_s1);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                  WHERE (e ->> 'id')::uuid = v_s1 AND e ->> 'status' = 'ended'
                    AND (e ->> 'duration_seconds')::int >= 0 AND (e ->> 'message_count')::int = 0
                    AND e -> 'featured_products' -> 0 ->> 'id' = v_product::text)
     OR v_json2 -> 'featured_products' -> 0 ->> 'id' IS DISTINCT FROM v_product::text
     OR v_json2 ->> 'shop_name' IS DISTINCT FROM v_shop_name
     OR (v_json ->> 'days')::int <> 30 THEN
    RAISE EXCEPTION '[5] geçmiş: % / %', v_json, v_json2;
  END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_json := public.live_history(50, 0, v_shop);
  EXECUTE 'RESET ROLE';
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'shop_id')::uuid <> v_shop)
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_s1) THEN
    RAISE EXCEPTION '[5] mağaza süzgeci: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [6] bekleme süresi: aynı mağazanın yeni yayını bildirim göndermez, günlüğe
  --     'cooldown' yazılır
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s2 := (public.live_create_session(v_shop, 'Yeniden bağlandım', NULL) ->> 'id')::uuid;
  v_json := public.start_live_session(v_s2);
  PERFORM public.end_live_session(v_s2);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'notified')::int <> 0
     OR EXISTS (SELECT 1 FROM public.notifications WHERE type = 'live_started' AND entity_id = v_s2::text)
     OR NOT EXISTS (SELECT 1 FROM public.live_notify_log WHERE session_id = v_s2 AND skipped = 'cooldown') THEN
    RAISE EXCEPTION '[6] bekleme süresi: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [7] bekleme 0 → yine aynı kitle; alıcı sınırı 1 → önce aboneler (en küçük kimlik)
  UPDATE public.app_settings SET value = '"0"'::jsonb WHERE key = 'live_notify_cooldown_hours';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s3 := (public.live_create_session(v_shop, 'Bekleme yok', NULL) ->> 'id')::uuid;
  v_json := public.start_live_session(v_s3);
  PERFORM public.end_live_session(v_s3);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'notified')::int <> v_n THEN RAISE EXCEPTION '[7] bekleme 0: % (beklenen %)', v_json, v_n; END IF;
  UPDATE public.app_settings SET value = '"1"'::jsonb WHERE key = 'live_notify_max_recipients';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s4 := (public.live_create_session(v_shop, 'Tek alıcı', NULL) ->> 'id')::uuid;
  v_json := public.start_live_session(v_s4);
  PERFORM public.end_live_session(v_s4);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'notified')::int <> 1
     OR (SELECT user_id FROM public.notifications WHERE type = 'live_started' AND entity_id = v_s4::text)
        IS DISTINCT FROM LEAST(v_u[1], v_u[6]) THEN
    RAISE EXCEPTION '[7] alıcı sınırı: %', v_json;
  END IF;
  UPDATE public.app_settings SET value = '"2000"'::jsonb WHERE key = 'live_notify_max_recipients';
  v_checks := v_checks + 1;

  -- [8] genel kapatma → 'disabled'; takipçi ve favori kitleleri kapalı → yalnız aboneler
  UPDATE public.app_settings SET value = '"false"'::jsonb WHERE key = 'live_notify_enabled';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s5 := (public.live_create_session(v_shop, 'Bildirim kapalı', NULL) ->> 'id')::uuid;
  v_json := public.start_live_session(v_s5);
  PERFORM public.end_live_session(v_s5);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'notified')::int <> 0
     OR EXISTS (SELECT 1 FROM public.notifications WHERE type = 'live_started' AND entity_id = v_s5::text)
     OR NOT EXISTS (SELECT 1 FROM public.live_notify_log WHERE session_id = v_s5 AND skipped = 'disabled') THEN
    RAISE EXCEPTION '[8] kapalıyken bildirdi: %', v_json;
  END IF;
  UPDATE public.app_settings SET value = '"true"'::jsonb WHERE key = 'live_notify_enabled';
  UPDATE public.app_settings SET value = '"false"'::jsonb WHERE key IN ('live_notify_followers', 'live_notify_product_fans');
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s6 := (public.live_create_session(v_shop, 'Yalnız aboneler', NULL) ->> 'id')::uuid;
  v_json := public.start_live_session(v_s6);
  PERFORM public.end_live_session(v_s6);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'notified')::int <> 2
     OR (SELECT array_agg(user_id ORDER BY user_id) FROM public.notifications
          WHERE type = 'live_started' AND entity_id = v_s6::text)
        IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(ARRAY[v_u[1], v_u[6]]) x) THEN
    RAISE EXCEPTION '[8] yalnız aboneler: %', v_json;
  END IF;
  UPDATE public.app_settings SET value = '"true"'::jsonb WHERE key IN ('live_notify_followers', 'live_notify_product_fans');
  v_checks := v_checks + 1;

  -- [9] geçmiş sayfaları: 2'şerlik sayfalar tek sayfayla aynı sıra, tekrarsız;
  --     gün ayarı okunur ve sınırlanır
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SELECT array_agg((e ->> 'id')::uuid ORDER BY o) INTO v_ids1
    FROM jsonb_array_elements(public.live_history(50, 0, v_shop) -> 'rows') WITH ORDINALITY t(e, o);
  SELECT array_agg((e ->> 'id')::uuid ORDER BY pg, o) INTO v_ids2
    FROM generate_series(0, 24) pg,
         LATERAL jsonb_array_elements(public.live_history(2, pg * 2, v_shop) -> 'rows') WITH ORDINALITY t(e, o);
  v_count := (public.live_history(2, 0, v_shop) ->> 'total')::int;
  EXECUTE 'RESET ROLE';
  IF v_ids1 IS DISTINCT FROM v_ids2 OR cardinality(v_ids1) < 6 OR cardinality(v_ids1) > 48
     OR v_count <> cardinality(v_ids1) THEN
    RAISE EXCEPTION '[9] sayfalar: % / % / %', v_ids1, v_ids2, v_count;
  END IF;
  UPDATE public.app_settings SET value = '"999"'::jsonb WHERE key = 'live_history_days';
  v_count := (public.live_history(1, 0, NULL) ->> 'days')::int;
  UPDATE public.app_settings SET value = '"abc"'::jsonb WHERE key = 'live_history_days';
  IF v_count <> 180 OR (public.live_history(1, 0, NULL) ->> 'days')::int <> 30 THEN
    RAISE EXCEPTION '[9] gün ayarı: %', v_count;
  END IF;
  UPDATE public.app_settings SET value = '"30"'::jsonb WHERE key = 'live_history_days';
  v_checks := v_checks + 1;

  -- [10] ana sayfa kartı: canlı yayın varken o, bitince son yayın; kart ya da
  --      modül kapalıysa enabled=false
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s7 := (public.live_create_session(v_shop, 'Ana sayfa kartı', NULL) ->> 'id')::uuid;
  PERFORM public.start_live_session(v_s7);
  PERFORM public.live_session_heartbeat(v_s7, 100000);
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_json := public.live_home_card();
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'enabled')::boolean IS NOT TRUE OR (v_json -> 'live' ->> 'id')::uuid IS DISTINCT FROM v_s7
     OR (v_json ->> 'live_count')::int < 1 OR (v_json -> 'last' ->> 'shop_id')::uuid IS DISTINCT FROM v_shop
     OR NOT (v_json -> 'last' ? 'featured_products') THEN
    RAISE EXCEPTION '[10] canlıyken kart: %', v_json;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  PERFORM public.end_live_session(v_s7);
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  v_json := public.live_home_card();
  EXECUTE 'RESET ROLE';
  IF (v_json -> 'live' ->> 'shop_id')::uuid IS NOT DISTINCT FROM v_shop
     OR (v_json -> 'last' ->> 'shop_id')::uuid IS DISTINCT FROM v_shop THEN
    RAISE EXCEPTION '[10] bitince kart: %', v_json;
  END IF;
  UPDATE public.app_settings SET value = '"false"'::jsonb WHERE key = 'live_home_card_enabled';
  v_json := public.live_home_card();
  UPDATE public.app_settings SET value = '"true"'::jsonb WHERE key = 'live_home_card_enabled';
  UPDATE public.app_settings SET value = '"false"'::jsonb WHERE key = 'live_stream_enabled';
  v_json2 := public.live_home_card();
  UPDATE public.app_settings SET value = '"true"'::jsonb WHERE key = 'live_stream_enabled';
  IF v_json <> '{"enabled": false}'::jsonb OR v_json2 <> '{"enabled": false}'::jsonb THEN
    RAISE EXCEPTION '[10] kapalı kart: % / %', v_json, v_json2;
  END IF;
  v_checks := v_checks + 1;

  -- [11] yönetici ayarları: yetki, sınırlar, düz metin kayıt, geçersiz girişler, sayaçlar
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_live_options('{"notify_enabled": false}'::jsonb);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[11] satıcı ayar değiştirdi: %', v_state; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_live_options(
    '{"notify_cooldown_hours": 500, "notify_enabled": false, "history_days": 0, "notify_max_recipients": 12.6, "notify_customers": true}'::jsonb);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'notify_cooldown_hours')::int <> 72 OR (v_json ->> 'notify_enabled')::boolean
     OR (v_json ->> 'history_days')::int <> 1 OR (v_json ->> 'notify_max_recipients')::int <> 13
     OR (v_json ->> 'notify_customers')::boolean IS NOT TRUE
     OR (SELECT value FROM public.app_settings WHERE key = 'live_notify_cooldown_hours') <> '"72"'::jsonb
     OR (SELECT value FROM public.app_settings WHERE key = 'live_notify_enabled') <> '"false"'::jsonb
     OR (v_json -> 'stats' ->> 'notifications_30d')::int < 4
     OR (v_json -> 'stats' ->> 'recipients_30d')::int < v_n
     OR (v_json -> 'stats' ->> 'cooldown_skips_30d')::int < 1
     OR (v_json -> 'stats' ->> 'subscriptions')::int < 5 THEN
    RAISE EXCEPTION '[11] ayarlar: %', v_json;
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_live_options('{"bilinmeyen": 1}'::jsonb);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_OPTIONS_INVALID' THEN RAISE EXCEPTION '[11] bilinmeyen anahtar: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_live_options('{"notify_cooldown_hours": "5"}'::jsonb);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_OPTIONS_INVALID' THEN RAISE EXCEPTION '[11] yanlış tür: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_live_options('[1]'::jsonb);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_OPTIONS_INVALID' THEN RAISE EXCEPTION '[11] dizi: %', v_hint; END IF;
  UPDATE public.app_settings SET value = '"true"'::jsonb WHERE key = 'live_notify_enabled';
  UPDATE public.app_settings SET value = '"false"'::jsonb WHERE key = 'live_notify_customers';
  UPDATE public.app_settings SET value = '"0"'::jsonb WHERE key = 'live_notify_cooldown_hours';
  UPDATE public.app_settings SET value = '"2000"'::jsonb WHERE key = 'live_notify_max_recipients';
  UPDATE public.app_settings SET value = '"30"'::jsonb WHERE key = 'live_history_days';
  v_checks := v_checks + 1;

  -- [12] yetkiler: misafir okur ama yazamaz/yönetemez; günlük istemciye kapalı;
  --      yeni tercih sütunu varsayılan açık
  IF NOT has_function_privilege('anon', 'public.live_history(integer, integer, uuid)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.live_home_card()', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.live_shop_subscription(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.live_session_detail(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.live_set_subscription(uuid, boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.admin_live_options()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.admin_set_live_options(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.start_live_session(uuid)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.live_notify_log', 'SELECT')
     OR has_table_privilege('anon', 'public.live_subscriptions', 'SELECT')
     OR has_table_privilege('authenticated', 'public.live_subscriptions', 'INSERT')
     OR NOT has_table_privilege('authenticated', 'public.live_subscriptions', 'SELECT')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'notification_preferences'
                       AND column_name = 'live_streams_enabled' AND column_default = 'true' AND is_nullable = 'NO') THEN
    RAISE EXCEPTION '[12] yetkiler';
  END IF;
  v_checks := v_checks + 1;

  -- [13] bildirim yazımı patlasa da yayın başlar (alt işlem geri alınır).
  --      Tabloya DDL kilidi aldığı için en sonda.
  EXECUTE $ddl$
    CREATE FUNCTION public.zz_test_live_notify_fail() RETURNS trigger
    LANGUAGE plpgsql AS $f$
    BEGIN
      IF NEW.type = 'live_started' THEN
        RAISE EXCEPTION 'yapay bildirim hatası';
      END IF;
      RETURN NEW;
    END;
    $f$
  $ddl$;
  EXECUTE 'CREATE TRIGGER zz_test_live_notify_fail BEFORE INSERT ON public.notifications
           FOR EACH ROW EXECUTE FUNCTION public.zz_test_live_notify_fail()';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s7 := (public.live_create_session(v_shop, 'Bildirim hatası', NULL) ->> 'id')::uuid;
  v_json := public.start_live_session(v_s7);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'live' OR v_json -> 'notified' <> 'null'::jsonb
     OR (SELECT status FROM public.live_sessions WHERE id = v_s7) <> 'live'
     OR EXISTS (SELECT 1 FROM public.live_notify_log WHERE session_id = v_s7) THEN
    RAISE EXCEPTION '[13] bildirim hatası yayını etkiledi: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
