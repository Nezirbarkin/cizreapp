-- Görev 4.5 — admin ana kategori kontrolü canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/admin_shop_category_control_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_shop uuid; v_shop_name text; v_owner uuid; v_admin uuid; v_other_user uuid;
  v_old_cat uuid; v_new_cat uuid; v_new_cat_name text; v_passive_cat uuid;
  v_json jsonb;
  v_hint text; v_state text;
  v_n integer;
  v_checks integer := 0;
BEGIN
  SELECT s.id, s.name, s.owner_id, s.category_id INTO v_shop, v_shop_name, v_owner, v_old_cat
    FROM public.shops s
   WHERE s.owner_id IS NOT NULL AND s.category_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.profiles p
                      WHERE p.id = s.owner_id AND (p.role::text = 'admin' OR COALESCE(p.is_admin, false)))
   ORDER BY s.created_at LIMIT 1;
  SELECT c.id, c.name INTO v_new_cat, v_new_cat_name FROM public.categories c
   WHERE COALESCE(c.is_active, true) AND c.id IS DISTINCT FROM v_old_cat
   ORDER BY c.display_order NULLS LAST, c.name LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_other_user FROM public.profiles
   WHERE id <> v_owner AND role::text <> 'admin' AND NOT COALESCE(is_admin, false) AND NOT COALESCE(is_bot, false)
   ORDER BY created_at LIMIT 1;
  IF v_shop IS NULL OR v_new_cat IS NULL OR v_admin IS NULL OR v_other_user IS NULL THEN
    RAISE EXCEPTION 'test verisi yok';
  END IF;
  DELETE FROM public.shop_category_locks WHERE shop_id = v_shop;
  INSERT INTO public.categories (id, name, slug, is_active)
  VALUES (gen_random_uuid(), 'Test pasif kategori', 'test-pasif-' || replace(gen_random_uuid()::text, '-', ''), false)
  RETURNING id INTO v_passive_cat;

  -- [1] satıcı yönetici RPC'sini çağıramaz
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_shop_category(v_shop, v_new_cat, false, NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[1] satıcı çağırdı: %', v_state; END IF;
  v_checks := v_checks + 1;

  -- [2] yönetici değiştirir + kilitler: kategori, kilit, denetim, satıcı bildirimi
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_shop_category(v_shop, v_new_cat, true, '  Yanlış kategori seçilmiş ');
  EXECUTE 'RESET ROLE';
  IF (SELECT category_id FROM public.shops WHERE id = v_shop) IS DISTINCT FROM v_new_cat
     OR NOT (v_json ->> 'changed')::boolean OR NOT (v_json ->> 'locked')::boolean
     OR v_json ->> 'category_name' <> v_new_cat_name
     OR NOT EXISTS (SELECT 1 FROM public.shop_category_locks
                     WHERE shop_id = v_shop AND note = 'Yanlış kategori seçilmiş' AND locked_by = v_admin)
     OR NOT EXISTS (SELECT 1 FROM public.admin_audit_log
                     WHERE action = 'set_shop_category' AND target_id = v_shop::text AND admin_id = v_admin
                       AND (old_data ->> 'category_id')::uuid = v_old_cat)
     OR NOT EXISTS (SELECT 1 FROM public.notifications
                     WHERE user_id = v_owner AND type = 'admin_notification' AND entity_id = v_shop::text
                       AND content LIKE '%' || v_new_cat_name || '%' AND content LIKE '%Yanlış kategori seçilmiş%') THEN
    RAISE EXCEPTION '[2] değiştirme: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [3] kilitliyken satıcı kategoriyi geri değiştiremez
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    UPDATE public.shops SET category_id = v_old_cat WHERE id = v_shop;
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'SHOP_CATEGORY_LOCKED' THEN RAISE EXCEPTION '[3] kilit delindi: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [4] kilitliyken satıcının diğer güncellemeleri (kategori aynı) çalışır
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  UPDATE public.shops SET description = COALESCE(description, '') || ' ', category_id = v_new_cat WHERE id = v_shop;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  EXECUTE 'RESET ROLE';
  IF v_n <> 1 THEN RAISE EXCEPTION '[4] satıcı güncellemesi engellendi (%)', v_n; END IF;
  v_checks := v_checks + 1;

  -- [5] kilidi satıcı okur, başkası okuyamaz
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_n FROM public.shop_category_locks WHERE shop_id = v_shop;
  IF v_n <> 1 THEN EXECUTE 'RESET ROLE'; RAISE EXCEPTION '[5] satıcı kilidini göremedi'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other_user, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_n FROM public.shop_category_locks WHERE shop_id = v_shop;
  EXECUTE 'RESET ROLE';
  IF v_n <> 0 THEN RAISE EXCEPTION '[5] başkası kilidi gördü'; END IF;
  v_checks := v_checks + 1;

  -- [6] pasif ya da olmayan kategoriye taşınmaz
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_shop_category(v_shop, v_passive_cat, true, NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'CATEGORY_INACTIVE' THEN RAISE EXCEPTION '[6] pasif: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_shop_category(v_shop, gen_random_uuid(), true, NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'CATEGORY_NOT_FOUND' THEN RAISE EXCEPTION '[6] olmayan: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [7] kilidi aç (kategori aynı): satıcı yeniden değiştirebilir, bilgilendirilir
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_shop_category(v_shop, v_new_cat, false, NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  UPDATE public.shops SET category_id = v_old_cat WHERE id = v_shop;
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'changed')::boolean OR (v_json ->> 'locked')::boolean
     OR EXISTS (SELECT 1 FROM public.shop_category_locks WHERE shop_id = v_shop)
     OR (SELECT category_id FROM public.shops WHERE id = v_shop) IS DISTINCT FROM v_old_cat
     OR NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_owner AND entity_id = v_shop::text
                     AND content LIKE '%yeniden kendin seçebilirsin%') THEN
    RAISE EXCEPTION '[7] kilit açma: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [8] Admin > Dükkanlar satırında kategori adı/kilit; kategori adıyla arama
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM public.admin_set_shop_category(v_shop, v_new_cat, true, 'Sabit');
  v_json := public.admin_shops_page(v_new_cat_name, NULL, 'name', 100, 0);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                  WHERE (e ->> 'id')::uuid = v_shop AND e ->> 'category_name' = v_new_cat_name
                    AND (e ->> 'category_locked')::boolean AND e ->> 'category_lock_note' = 'Sabit') THEN
    RAISE EXCEPTION '[8] admin satırı: %', v_json -> 'rows';
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
