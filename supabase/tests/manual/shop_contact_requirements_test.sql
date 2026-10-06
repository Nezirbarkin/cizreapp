-- Görev 3.7 — satıcı telefon + konum zorunluluğu canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/shop_contact_requirements_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_full uuid; v_full_owner uuid;       -- telefon + konumu olan mağaza
  v_missing uuid; v_missing_owner uuid; -- konumu olmayan mağaza
  v_new_owner uuid;                     -- mağazası olmayan kullanıcı
  v_admin uuid;
  v_hint text; v_state text;
  v_checks integer := 0;
BEGIN
  SELECT id, owner_id INTO v_full, v_full_owner FROM public.shops
   WHERE public.shop_phone_is_valid(phone) AND latitude IS NOT NULL AND longitude IS NOT NULL
   ORDER BY created_at LIMIT 1;
  SELECT id, owner_id INTO v_missing, v_missing_owner FROM public.shops
   WHERE (latitude IS NULL OR longitude IS NULL) AND owner_id <> v_full_owner
   ORDER BY created_at LIMIT 1;
  SELECT id INTO v_new_owner FROM public.profiles
   WHERE id NOT IN (SELECT owner_id FROM public.shops) AND NOT COALESCE(is_admin, false) AND role::text <> 'admin'
   ORDER BY created_at LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  IF v_full IS NULL OR v_missing IS NULL OR v_new_owner IS NULL OR v_admin IS NULL THEN
    RAISE EXCEPTION 'test verisi yok';
  END IF;

  -- [1] yapı + telefon biçimi
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.shops'::regclass AND tgname = 'trg_shops_guard_contact_info')
     OR (SELECT prosecdef FROM pg_proc WHERE oid = 'public.guard_shop_contact_info()'::regprocedure) THEN
    RAISE EXCEPTION '[1] tetikleyici yok ya da DEFINER';
  END IF;
  IF NOT public.shop_phone_is_valid('0532 123 45 67') OR NOT public.shop_phone_is_valid('+90 (532) 123-4567')
     OR NOT public.shop_phone_is_valid('5321234567') OR public.shop_phone_is_valid('123456')
     OR public.shop_phone_is_valid('') OR public.shop_phone_is_valid(NULL) THEN
    RAISE EXCEPTION '[1] telefon biçimi';
  END IF;
  v_checks := v_checks + 1;

  -- [2] dolu telefon/konum silinemez, geçersize çevrilemez
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_full_owner, 'role', 'authenticated')::text, true);
    UPDATE public.shops SET phone = '' WHERE id = v_full;
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'SHOP_PHONE_REQUIRED' THEN RAISE EXCEPTION '[2] telefon silindi: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_full_owner, 'role', 'authenticated')::text, true);
    UPDATE public.shops SET phone = '0532 12' WHERE id = v_full;
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'SHOP_PHONE_REQUIRED' THEN RAISE EXCEPTION '[2] kısa telefon: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_full_owner, 'role', 'authenticated')::text, true);
    UPDATE public.shops SET latitude = NULL WHERE id = v_full;
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'SHOP_LOCATION_REQUIRED' THEN RAISE EXCEPTION '[2] konum silindi: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_full_owner, 'role', 'authenticated')::text, true);
    UPDATE public.shops SET latitude = 95, longitude = 42 WHERE id = v_full;  -- sütun 100+ değeri zaten reddeder (numeric taşması)
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = MESSAGE_TEXT;
  END;
  IF v_hint IS DISTINCT FROM 'SHOP_LOCATION_INVALID' THEN RAISE EXCEPTION '[2] geçersiz konum: % %', v_hint, v_state; END IF;
  -- geçerli değişiklik serbest
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_full_owner, 'role', 'authenticated')::text, true);
  UPDATE public.shops SET phone = '0532 999 88 77', latitude = 37.33, longitude = 42.19 WHERE id = v_full;
  EXECUTE 'RESET ROLE';
  IF (SELECT phone FROM public.shops WHERE id = v_full) <> '0532 999 88 77' THEN RAISE EXCEPTION '[2] geçerli güncelleme olmadı'; END IF;
  v_checks := v_checks + 1;

  -- [3] eksik mağaza kilitlenmez: diğer alanlar güncellenir, konumu eklenebilir
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_missing_owner, 'role', 'authenticated')::text, true);
  UPDATE public.shops SET description = COALESCE(description, '') || ' ' WHERE id = v_missing;
  UPDATE public.shops SET latitude = 37.32, longitude = 42.18 WHERE id = v_missing;
  EXECUTE 'RESET ROLE';
  IF (SELECT latitude FROM public.shops WHERE id = v_missing) IS NULL THEN RAISE EXCEPTION '[3] konum eklenemedi'; END IF;
  v_checks := v_checks + 1;

  -- [4] yeni mağaza telefon + konum olmadan açılmaz
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_new_owner, 'role', 'authenticated')::text, true);
    INSERT INTO public.shops (owner_id, name, slug, is_active, is_approved)
    VALUES (v_new_owner, 'Test Dükkan', 'test-dukkan-' || substr(md5(random()::text), 1, 8), true, false);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = MESSAGE_TEXT;
  END;
  IF v_hint IS DISTINCT FROM 'SHOP_PHONE_REQUIRED' THEN RAISE EXCEPTION '[4] telefonsuz mağaza: % %', v_hint, v_state; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_new_owner, 'role', 'authenticated')::text, true);
    INSERT INTO public.shops (owner_id, name, slug, is_active, is_approved, phone)
    VALUES (v_new_owner, 'Test Dükkan', 'test-dukkan-' || substr(md5(random()::text), 1, 8), true, false, '05321234567');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = MESSAGE_TEXT;
  END;
  IF v_hint IS DISTINCT FROM 'SHOP_LOCATION_REQUIRED' THEN RAISE EXCEPTION '[4] konumsuz mağaza: % %', v_hint, v_state; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_new_owner, 'role', 'authenticated')::text, true);
  INSERT INTO public.shops (owner_id, name, slug, is_active, is_approved, phone, latitude, longitude, address)
  VALUES (v_new_owner, 'Test Dükkan', 'test-dukkan-' || substr(md5(random()::text), 1, 8), true, false,
          '05321234567', 37.33, 42.19, 'Cizre');
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM public.shops WHERE owner_id = v_new_owner) THEN RAISE EXCEPTION '[4] tam mağaza açılmadı'; END IF;
  v_checks := v_checks + 1;

  -- [5] yönetici serbest (panelden eksik bilgiyle mağaza açabilir/düzenleyebilir)
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  UPDATE public.shops SET phone = NULL WHERE id = v_full;
  EXECUTE 'RESET ROLE';
  IF (SELECT phone FROM public.shops WHERE id = v_full) IS NOT NULL THEN RAISE EXCEPTION '[5] yönetici değiştiremedi'; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
