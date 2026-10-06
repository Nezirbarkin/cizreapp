-- Görev 4.2 — admin sponsorluk yönetimi canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/admin_sponsorship_management_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_shop uuid; v_owner uuid; v_admin uuid;
  v_pkg uuid; v_price numeric; v_days integer;
  v_s1 uuid; v_s2 uuid; v_s3 uuid;
  v_p1 uuid; v_p2 uuid; v_expected uuid[]; v_got uuid[]; v_n integer;
  v_json jsonb;
  v_balance numeric;
  v_hint text; v_state text;
  v_row public.shop_sponsorships%ROWTYPE;
  v_checks integer := 0;
BEGIN
  SELECT s.id, s.owner_id INTO v_shop, v_owner FROM public.shops s
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT id, price, duration_days INTO v_pkg, v_price, v_days FROM public.sponsorship_packages
   WHERE placement = 'shop_list' AND is_active ORDER BY duration_days LIMIT 1;
  IF v_shop IS NULL OR v_admin IS NULL OR v_pkg IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;

  -- Temiz başlangıç: bu mağazanın öne çıkarmaları yok, sahibe 1000 TL bakiye
  DELETE FROM public.shop_sponsorships WHERE shop_id = v_shop;
  UPDATE public.shops SET sponsored_list_until = NULL WHERE id = v_shop;
  INSERT INTO public.user_balances (user_id, balance) VALUES (v_owner, 1000)
  ON CONFLICT (user_id) DO UPDATE SET balance = 1000;
  UPDATE public.app_settings SET value = 'true'::jsonb WHERE key = 'sponsorship_enabled';
  UPDATE public.app_settings SET value = 'true'::jsonb WHERE key = 'sponsorship_requires_approval';

  -- [1] yönetici olmayan liste/karar çağıramaz
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.admin_sponsorships_list('pending', 10, 0);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[1] satıcı listeyi gördü: %', v_state; END IF;
  v_checks := v_checks + 1;

  -- [2] onay gerekirken satın alma 'pending'; admin listede ve özette görür
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_json := public.purchase_shop_sponsorship(v_shop, v_pkg, NULL);
  v_s1 := (v_json ->> 'id')::uuid;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_sponsorships_list('pending', 50, 0);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_s1 AND e ->> 'shop_name' IS NOT NULL)
     OR (v_json -> 'summary' ->> 'pending')::int < 1
     OR NOT (v_json -> 'settings' ->> 'requires_approval')::boolean THEN
    RAISE EXCEPTION '[2] bekleyen liste: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [3] ret: ücret iade, satıcıya bildirim
  SELECT balance INTO v_balance FROM public.user_balances WHERE user_id = v_owner;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_review_sponsorship(v_s1, false, 'Görsel uygun değil');
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'rejected' OR (v_json ->> 'refunded')::numeric <> v_price
     OR (SELECT balance FROM public.user_balances WHERE user_id = v_owner) <> v_balance + v_price THEN
    RAISE EXCEPTION '[3] ret/iade: %', v_json;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.balance_transactions WHERE reference_id = v_s1 AND type = 'refund')
     OR NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_owner AND type = 'sponsorship_update'
                     AND entity_id = v_s1::text AND content LIKE '%Görsel uygun değil%') THEN
    RAISE EXCEPTION '[3] iade kaydı ya da bildirim yok';
  END IF;
  v_checks := v_checks + 1;

  -- [4] onay: şimdi başlar, vitrin sütunu dolar
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s2 := (public.purchase_shop_sponsorship(v_shop, v_pkg, NULL) ->> 'id')::uuid;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_review_sponsorship(v_s2, true, NULL);
  EXECUTE 'RESET ROLE';
  SELECT * INTO v_row FROM public.shop_sponsorships WHERE id = v_s2;
  IF v_row.status <> 'active' OR v_row.starts_at > now() + interval '1 second'
     OR v_row.ends_at <> v_row.starts_at + make_interval(days => v_days)
     OR (SELECT sponsored_list_until FROM public.shops WHERE id = v_shop) IS DISTINCT FROM v_row.ends_at THEN
    RAISE EXCEPTION '[4] onay: % %', v_json, v_row;
  END IF;
  v_checks := v_checks + 1;

  -- [5] sıradaki + süreni iadeli iptal: sıradaki öne çekilir
  UPDATE public.app_settings SET value = 'false'::jsonb WHERE key = 'sponsorship_requires_approval';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_s3 := (public.purchase_shop_sponsorship(v_shop, v_pkg, NULL) ->> 'id')::uuid;
  EXECUTE 'RESET ROLE';
  IF (SELECT starts_at FROM public.shop_sponsorships WHERE id = v_s3) <> v_row.ends_at THEN
    RAISE EXCEPTION '[5] sıradaki zincirin sonundan başlamadı';
  END IF;
  SELECT balance INTO v_balance FROM public.user_balances WHERE user_id = v_owner;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_cancel_sponsorship(v_s2, true, 'Kural ihlali');
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'cancelled' OR (v_json ->> 'refunded')::numeric < v_price - 0.05
     OR (SELECT balance FROM public.user_balances WHERE user_id = v_owner) < v_balance + v_price - 0.05 THEN
    RAISE EXCEPTION '[5] iadeli iptal: %', v_json;
  END IF;
  SELECT * INTO v_row FROM public.shop_sponsorships WHERE id = v_s3;
  IF v_row.starts_at > now() + interval '1 second'
     OR (SELECT sponsored_list_until FROM public.shops WHERE id = v_shop) IS DISTINCT FROM v_row.ends_at THEN
    RAISE EXCEPTION '[5] sıradaki öne çekilmedi: %', v_row;
  END IF;
  v_checks := v_checks + 1;

  -- [6] iadesiz iptal: bakiye değişmez; vitrin boşalır
  SELECT balance INTO v_balance FROM public.user_balances WHERE user_id = v_owner;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_cancel_sponsorship(v_s3, false, NULL);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'refunded')::numeric <> 0 OR (SELECT balance FROM public.user_balances WHERE user_id = v_owner) <> v_balance
     OR (SELECT sponsored_list_until FROM public.shops WHERE id = v_shop) IS NOT NULL THEN
    RAISE EXCEPTION '[6] iadesiz iptal: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [7] sonuçlanmışa karar / bitmişe iptal reddedilir
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_review_sponsorship(v_s1, true, NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'SPONSORSHIP_NOT_PENDING' THEN RAISE EXCEPTION '[7] tekrar karar: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_cancel_sponsorship(v_s3, true, NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'SPONSORSHIP_NOT_ACTIVE' THEN RAISE EXCEPTION '[7] tekrar iptal: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [8] sayfa kesimi = sayfa içi sıra: limit 1'lik sayfalar bekleyenleri en eskiden verir
  UPDATE public.app_settings SET value = 'true'::jsonb WHERE key = 'sponsorship_requires_approval';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_p1 := (public.purchase_shop_sponsorship(v_shop, v_pkg, NULL) ->> 'id')::uuid;
  v_p2 := (public.purchase_shop_sponsorship(v_shop, v_pkg, NULL) ->> 'id')::uuid;
  EXECUTE 'RESET ROLE';
  UPDATE public.shop_sponsorships SET created_at = now() - interval '1 hour' WHERE id = v_p2;
  SELECT array_agg(id ORDER BY created_at, id) INTO v_expected FROM public.shop_sponsorships WHERE status = 'pending';
  v_n := LEAST(COALESCE(array_length(v_expected, 1), 0), 10);
  v_got := ARRAY[]::uuid[];
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  FOR i IN 0 .. v_n - 1 LOOP
    v_got := v_got || (public.admin_sponsorships_list('pending', 1, i) -> 'rows' -> 0 ->> 'id')::uuid;
  END LOOP;
  EXECUTE 'RESET ROLE';
  IF v_n < 2 OR v_got IS DISTINCT FROM v_expected[1:v_n]
     OR (array_position(v_got, v_p1) IS NOT NULL AND array_position(v_got, v_p2) > array_position(v_got, v_p1)) THEN
    RAISE EXCEPTION '[8] bekleyen sayfa sırası: beklenen % gelen %', v_expected[1:v_n], v_got;
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
