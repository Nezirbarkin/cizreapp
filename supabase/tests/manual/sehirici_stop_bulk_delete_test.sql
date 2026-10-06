-- Görev 3.10 — şehiriçi durak toplu silme + mantık düzeltmeleri canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/sehirici_stop_bulk_delete_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_admin uuid;
  v_user uuid;
  v_city uuid;
  v_city2 uuid;
  v_line uuid;
  v_s uuid[] := ARRAY[]::uuid[];
  v_id uuid;
  v_json jsonb;
  v_orders integer[];
  v_hint text; v_msg text;
  v_n integer;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_user FROM public.profiles WHERE role::text = 'customer' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_city FROM public.sehirici_cities ORDER BY created_at LIMIT 1;
  IF v_admin IS NULL OR v_user IS NULL OR v_city IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;

  -- Test şehri, hattı ve 5 durak
  INSERT INTO public.sehirici_cities (name, slug, center_lat, center_lng, zoom_level, is_active)
  VALUES ('Test Şehri', 'test-sehri-' || substr(md5(random()::text), 1, 6), 37.2, 42.4, 14, false)
  RETURNING id INTO v_city2;
  INSERT INTO public.sehirici_lines (city_id, code, name, color_hex, vehicle_type, is_active, display_order)
  VALUES (v_city, 'TST', 'Test hattı', '#FF0000', 'bus', true, 999)
  RETURNING id INTO v_line;
  FOR v_n IN 1..5 LOOP
    INSERT INTO public.sehirici_stops (city_id, name, lat, lng, is_active)
    VALUES (v_city, 'Test durağı ' || v_n, 37.32 + v_n * 0.001, 42.19, true)
    RETURNING id INTO v_id;
    v_s := v_s || v_id;
  END LOOP;

  -- [1] yapı/yetki
  IF has_function_privilege('anon', 'public.admin_delete_sehirici_stops(uuid[])', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] anon toplu silebiliyor';
  END IF;
  v_checks := v_checks + 1;

  -- [2] hat durakları: yinelenen/boşluklu sıra sunucuda 0..n-1 olur
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_n := public.admin_set_sehirici_line_stops(v_line, jsonb_build_array(
    jsonb_build_object('stop_id', v_s[1], 'stop_order', 0),
    jsonb_build_object('stop_id', v_s[2], 'stop_order', 5),
    jsonb_build_object('stop_id', v_s[3], 'stop_order', 5),   -- aynı sıra: eskiden UNIQUE ile düşerdi
    jsonb_build_object('stop_id', v_s[4], 'stop_order', 9),
    jsonb_build_object('stop_id', v_s[5], 'stop_order', 12)
  ));
  EXECUTE 'RESET ROLE';
  SELECT array_agg(stop_order ORDER BY stop_order) INTO v_orders FROM public.sehirici_line_stops WHERE line_id = v_line;
  IF v_n <> 5 OR v_orders <> ARRAY[0,1,2,3,4] THEN RAISE EXCEPTION '[2] sıra: % %', v_n, v_orders; END IF;
  IF (SELECT stop_id FROM public.sehirici_line_stops WHERE line_id = v_line AND stop_order = 2) <> v_s[3] THEN
    RAISE EXCEPTION '[2] eşit sırada dizi yeri korunmadı';
  END IF;
  v_checks := v_checks + 1;

  -- [3] yönetici olmayan toplu silemez
  v_msg := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    PERFORM public.admin_delete_sehirici_stops(ARRAY[v_s[1]]);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  IF v_msg NOT LIKE '%admin yetkisi%' THEN RAISE EXCEPTION '[3] kullanıcı sildi: %', v_msg; END IF;
  v_checks := v_checks + 1;

  -- [4] toplu silme: 2. ve 4. durak gider, kalanlar 0..2; etkilenen hat raporlanır
  UPDATE public.sehirici_lines SET route_polyline = '{"points":[[37.3,42.1],[37.4,42.2]],"stops_signature":"x"}'::jsonb WHERE id = v_line;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_delete_sehirici_stops(ARRAY[v_s[2], v_s[4]]);
  EXECUTE 'RESET ROLE';
  SELECT array_agg(stop_order ORDER BY stop_order) INTO v_orders FROM public.sehirici_line_stops WHERE line_id = v_line;
  IF (v_json ->> 'deleted')::int <> 2 OR v_orders <> ARRAY[0,1,2] THEN RAISE EXCEPTION '[4] silme: % %', v_json, v_orders; END IF;
  IF (v_json -> 'affected_lines' -> 0 ->> 'code') <> 'TST' OR (v_json -> 'affected_lines' -> 0 ->> 'remaining_stops')::int <> 3 THEN
    RAISE EXCEPTION '[4] etkilenen hat raporu: %', v_json;
  END IF;
  IF (SELECT route_polyline FROM public.sehirici_lines WHERE id = v_line) IS NULL THEN
    RAISE EXCEPTION '[4] 3 duraklı hattın rotası gereksiz silindi';
  END IF;
  v_checks := v_checks + 1;

  -- [5] tek silme de yeniden numaralar; 2'den az durak kalınca rota temizlenir
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM public.admin_delete_sehirici_stop(v_s[1]);
  PERFORM public.admin_delete_sehirici_stop(v_s[3]);
  EXECUTE 'RESET ROLE';
  SELECT array_agg(stop_order ORDER BY stop_order) INTO v_orders FROM public.sehirici_line_stops WHERE line_id = v_line;
  IF v_orders <> ARRAY[0] OR (SELECT route_polyline FROM public.sehirici_lines WHERE id = v_line) IS NOT NULL THEN
    RAISE EXCEPTION '[5] tek silme: %', v_orders;
  END IF;
  v_checks := v_checks + 1;

  -- [6] durak kaydı: boş ad, aralık dışı konum, hatta kullanılırken şehir değişimi reddedilir
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_upsert_sehirici_stop(v_s[5], v_city, '   ', NULL, 37.3, 42.1, true);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'SEHIRICI_STOP_NAME_REQUIRED' THEN RAISE EXCEPTION '[6] boş ad: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_upsert_sehirici_stop(v_s[5], v_city, 'Durak', NULL, 137.3, 42.1, true);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'SEHIRICI_STOP_LOCATION_INVALID' THEN RAISE EXCEPTION '[6] konum: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_upsert_sehirici_stop(v_s[5], v_city2, 'Durak', NULL, 37.3, 42.1, true);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'SEHIRICI_STOP_CITY_IN_USE' THEN RAISE EXCEPTION '[6] şehir değişimi: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [7] pasif durak kullanıcı hat listesinde yok
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM public.admin_upsert_sehirici_stop(v_s[5], v_city, 'Test durağı 5', NULL, 37.325, 42.19, false);
  EXECUTE 'RESET ROLE';
  SELECT jsonb_array_length(stops) INTO v_n FROM public.get_sehirici_lines_with_stops(v_city) WHERE line_id = v_line;
  IF v_n <> 0 THEN RAISE EXCEPTION '[7] pasif durak kullanıcıya gidiyor: %', v_n; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
