-- Görev 4.3 — admin canlı yayın kontrolü canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/admin_live_stream_controls_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_shop uuid; v_shop_name text; v_owner uuid; v_admin uuid;
  v_s uuid;
  v_json jsonb;
  v_hint text; v_detail text; v_state text;
  v_row public.live_sessions%ROWTYPE;
  v_checks integer := 0;
BEGIN
  SELECT s.id, s.name, s.owner_id INTO v_shop, v_shop_name, v_owner
    FROM public.shops s
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) AND s.owner_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.profiles p
                      WHERE p.id = s.owner_id AND (p.role::text = 'admin' OR COALESCE(p.is_admin, false)))
   ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  IF v_shop IS NULL OR v_admin IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;

  -- Temiz başlangıç
  DELETE FROM public.live_sessions WHERE shop_id = v_shop AND status IN ('scheduled', 'live');
  DELETE FROM public.shop_live_permissions WHERE shop_id = v_shop;
  UPDATE public.app_settings SET value = '"true"'::jsonb WHERE key = 'live_stream_enabled';
  UPDATE public.app_settings SET value = '"open"'::jsonb WHERE key = 'live_stream_access';

  -- [1] yönetici olmayan yönetim RPC'lerini çağıramaz
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_shop_live_permission(v_shop, 'granted', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[1] satıcı kendine izin verdi: %', v_state; END IF;
  v_checks := v_checks + 1;

  -- [2] açık mod, izin kaydı yok: satıcı yayın açar ve başlatır
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s := (public.live_create_session(v_shop, 'Test yayını', NULL) ->> 'id')::uuid;
  v_json := public.start_live_session(v_s);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'live' THEN RAISE EXCEPTION '[2] başlamadı: %', v_json; END IF;
  v_checks := v_checks + 1;

  -- [3] yönetici listesi: satır, özet ve ayarlar
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_live_sessions('live', 100, 0);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                  WHERE (e ->> 'id')::uuid = v_s AND e ->> 'shop_access' = 'ok' AND e ? 'host_name'
                    AND e ->> 'shop_name' = v_shop_name)
     OR (v_json -> 'summary' ->> 'live_now')::int < 1
     OR (v_json -> 'settings' ->> 'enabled')::boolean IS NOT TRUE
     OR v_json -> 'settings' ->> 'access' <> 'open' THEN
    RAISE EXCEPTION '[3] liste: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [4] yönetici yayını notla kapatır, satıcıya bildirim; ikinci kez → LIVE_ENDED
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_end_live_session(v_s, '  Uygunsuz içerik ');
  EXECUTE 'RESET ROLE';
  SELECT * INTO v_row FROM public.live_sessions WHERE id = v_s;
  IF v_row.status <> 'ended' OR v_row.ended_reason <> 'admin' OR v_row.ended_note <> 'Uygunsuz içerik'
     OR v_row.ended_by <> v_admin OR v_json ->> 'ended_reason' <> 'admin' THEN
    RAISE EXCEPTION '[4] kapatma: % / %', v_json, v_row;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications
                  WHERE user_id = v_owner AND type = 'admin_notification'
                    AND entity_id = v_s::text AND content LIKE '%Uygunsuz içerik%') THEN
    RAISE EXCEPTION '[4] satıcıya bildirim yok';
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_end_live_session(v_s, NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_ENDED' THEN RAISE EXCEPTION '[4] tekrar kapatma: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [5] izin kaldırılınca hazırlıktaki yayın silinir; yenisi LIVE_REVOKED + not; bildirim
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s := (public.live_create_session(v_shop, 'Hazırlık', NULL) ->> 'id')::uuid;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_shop_live_permission(v_shop, 'revoked', 'Kurallara aykırı yayın');
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'closed')::int <> 1 OR v_json ->> 'effective' <> 'LIVE_REVOKED' OR v_json ->> 'permission' <> 'revoked'
     OR EXISTS (SELECT 1 FROM public.live_sessions WHERE id = v_s) THEN
    RAISE EXCEPTION '[5] kaldırma: %', v_json;
  END IF;
  v_hint := NULL; v_detail := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.live_create_session(v_shop, 'Yeni deneme', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_detail = PG_EXCEPTION_DETAIL;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_REVOKED' OR v_detail IS DISTINCT FROM 'Kurallara aykırı yayın' THEN
    RAISE EXCEPTION '[5] izinsizken açtı: % / %', v_hint, v_detail;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications
                  WHERE user_id = v_owner AND type = 'admin_notification' AND entity_id = v_shop::text
                    AND title = 'Canlı yayın iznin kaldırıldı' AND content LIKE '%Kurallara aykırı yayın%') THEN
    RAISE EXCEPTION '[5] izin bildirimi yok';
  END IF;
  v_checks := v_checks + 1;

  -- [6] mağaza listesi: arama + 'revoked' süzgeci, not ve etkin durum
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_live_shops(v_shop_name, 'revoked', 50, 0);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                  WHERE (e ->> 'shop_id')::uuid = v_shop AND e ->> 'permission' = 'revoked'
                    AND e ->> 'note' = 'Kurallara aykırı yayın' AND e ->> 'effective' = 'LIVE_REVOKED'
                    AND (e ->> 'session_count')::int >= 1)
     OR (v_json -> 'summary' ->> 'revoked')::int < 1 THEN
    RAISE EXCEPTION '[6] mağaza listesi: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [7] davet modu: kayıt yoksa LIVE_NOT_PERMITTED; izin verilince açar, "açıldı" bildirimi
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM public.admin_set_live_settings(NULL, 'invite', false);
  v_json := public.admin_set_shop_live_permission(v_shop, 'default', NULL);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'effective' <> 'LIVE_NOT_PERMITTED' OR v_json -> 'permission' <> 'null'::jsonb THEN
    RAISE EXCEPTION '[7] davet modu: %', v_json;
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.live_create_session(v_shop, 'Davetsiz', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_NOT_PERMITTED' THEN RAISE EXCEPTION '[7] davetsiz açtı: %', v_hint; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_shop_live_permission(v_shop, 'granted', NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s := (public.live_create_session(v_shop, 'İzinli yayın', NULL) ->> 'id')::uuid;
  PERFORM public.start_live_session(v_s);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'effective' <> 'ok'
     OR NOT EXISTS (SELECT 1 FROM public.notifications
                     WHERE user_id = v_owner AND type = 'admin_notification' AND entity_id = v_shop::text
                       AND title = 'Canlı yayın iznin açıldı')
     OR (SELECT status FROM public.live_sessions WHERE id = v_s) <> 'live' THEN
    RAISE EXCEPTION '[7] izinli yayın: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [8] genel kapatma (süreni kapatmadan): süren yayının anahtar yenilemesi ve
  --     izleyicisi sürer, akış kapalı der; yeni yayın ve hazırlıktakinin anahtarı reddedilir
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_live_settings(false, NULL, false);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'closed')::int <> 0 OR (v_json ->> 'enabled')::boolean THEN
    RAISE EXCEPTION '[8] ayar: %', v_json;
  END IF;
  IF (public.live_token_grant(v_s, 'host', v_owner) ->> 'ok')::boolean IS NOT TRUE
     OR (public.live_token_grant(v_s, 'viewer', NULL) ->> 'ok')::boolean IS NOT TRUE
     OR (public.live_sessions_feed(10) ->> 'enabled')::boolean THEN
    RAISE EXCEPTION '[8] süren yayın kesildi ya da akış açık diyor';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  PERFORM public.end_live_session(v_s);
  EXECUTE 'RESET ROLE';
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.live_create_session(v_shop, 'Kapalıyken', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_DISABLED' THEN RAISE EXCEPTION '[8] kapalıyken açtı: %', v_hint; END IF;
  INSERT INTO public.live_sessions (host_user_id, shop_id, title, channel_name, status)
  VALUES (v_owner, v_shop, 'Eski hazırlık', 'cz_test_' || replace(gen_random_uuid()::text, '-', ''), 'scheduled')
  RETURNING id INTO v_s;
  IF public.live_token_grant(v_s, 'host', v_owner) ->> 'error' IS DISTINCT FROM 'LIVE_DISABLED' THEN
    RAISE EXCEPTION '[8] hazırlıktakine anahtar verildi';
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.start_live_session(v_s);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_DISABLED' THEN RAISE EXCEPTION '[8] kapalıyken başlattı: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [9] "süren yayınları da kapat": artık izinsiz olan canlı yayın 'admin' nedeniyle biter
  UPDATE public.live_sessions
     SET status = 'live', started_at = now(), last_heartbeat_at = now()
   WHERE id = v_s;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_live_settings(NULL, NULL, true);
  EXECUTE 'RESET ROLE';
  SELECT * INTO v_row FROM public.live_sessions WHERE id = v_s;
  IF (v_json ->> 'closed')::int < 1 OR v_row.status <> 'ended' OR v_row.ended_reason <> 'admin' THEN
    RAISE EXCEPTION '[9] toplu kapatma: % / %', v_json, v_row;
  END IF;
  v_checks := v_checks + 1;

  -- [10] geçersiz değerler reddedilir
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_live_settings(NULL, 'herkes', false);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_ACCESS_INVALID' THEN RAISE EXCEPTION '[10] mod: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_shop_live_permission(v_shop, 'belki', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'LIVE_PERMISSION_INVALID' THEN RAISE EXCEPTION '[10] izin: %', v_hint; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
