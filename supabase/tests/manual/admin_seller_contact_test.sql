-- =============================================================================
-- Admin satıcı bilgileri (20261028000001) — sunucu testi
--   supabase db query --linked --file supabase/tests/manual/admin_seller_contact_test.sql
--
-- Neyi kanıtlar:
--   [A]  admin olmayan admin_shops_page / admin_user_detail için 42501 alır;
--        anon ikisini de çağıramaz
--   [C]  TÜM canlı dükkanlarda satırdaki phone/email/address/latitude/
--        longitude/iban/bank_name/account_holder_name = shops tablosu;
--        profiles.phone = sahibin profili
--   [K]  eski anahtarlar yerinde (profiles, product_count, net_earnings,
--        category_name, scheduled_orders_enabled …)
--   [Q]  arama dükkan telefonunun bir parçasıyla dükkanı bulur
--   [U]  admin_user_detail satıcı için shop_id + shop_phone döndürür,
--        dükkanı olmayan kullanıcıda ikisi de NULL
--
-- Betik TEK DO bloğudur ve SONUNDA bilerek istisna fırlatır: her şey geri alınır.
--   BAŞARILI:  "TESTS_PASSED ..."    BAŞARISIZ: "TEST_FAIL[x]: ..."
-- =============================================================================

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAIL[%]', p_label;
  END IF;
  PERFORM set_config('t.n', (COALESCE(NULLIF(current_setting('t.n', true), ''), '0')::int + 1)::text, true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true)
$$;

DO $test$
DECLARE
  v_admin uuid;
  v_user uuid;
  v_all jsonb;
  v_row jsonb;
  v_found jsonb;
  v_detail jsonb;
  v_shop_count int;
  v_with_phone int := 0;
  v_probe_shop uuid;
  v_probe text;
  v_owner uuid;
  r record;
BEGIN
  PERFORM set_config('t.n', '0', true);
  SELECT id INTO v_admin FROM public.profiles
   WHERE role = 'admin'::public.user_role ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_user FROM public.profiles p
   WHERE p.role = 'customer'::public.user_role
     AND NOT EXISTS (SELECT 1 FROM public.shops s WHERE s.owner_id = p.id)
   ORDER BY p.created_at LIMIT 1;
  IF v_admin IS NULL OR v_user IS NULL THEN
    RAISE EXCEPTION 'TEST_FAIL[setup]: admin ve dükkansız müşteri profili gerekli';
  END IF;
  SELECT count(*) INTO v_shop_count FROM public.shops;

  -- ------------------------------------------------------------------ yetki
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM pg_temp.as_user(v_user);
    PERFORM public.admin_shops_page();
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[A1]: admin olmayan dükkan listesini aldı';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'A1');

  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM pg_temp.as_user(v_user);
    PERFORM public.admin_user_detail(v_admin);
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[A2]: admin olmayan kullanıcı detayını aldı';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'A2');

  PERFORM pg_temp.ok(NOT has_function_privilege('anon',
    'public.admin_shops_page(text,text,text,integer,integer)', 'EXECUTE'), 'A3 anon liste');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon',
    'public.admin_user_detail(uuid)', 'EXECUTE'), 'A4 anon detay');

  -- ------------------------------------------------- admin gözüyle tam liste
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.as_user(v_admin);
  v_all := public.admin_shops_page(NULL, NULL, 'default', 100, 0);
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(jsonb_array_length(v_all->'rows') = LEAST(v_shop_count, 100), 'C0 tüm dükkanlar');

  FOR r IN
    SELECT s.*, pf.phone AS owner_phone
      FROM public.shops s
      LEFT JOIN public.profiles pf ON pf.id = s.owner_id
  LOOP
    SELECT e INTO v_row FROM jsonb_array_elements(v_all->'rows') e
     WHERE (e->>'id')::uuid = r.id;
    PERFORM pg_temp.ok(v_row IS NOT NULL, 'C1 satır var ' || r.id);
    PERFORM pg_temp.ok((v_row->>'phone') IS NOT DISTINCT FROM r.phone, 'C2 phone ' || r.id);
    PERFORM pg_temp.ok((v_row->>'email') IS NOT DISTINCT FROM r.email, 'C3 email ' || r.id);
    PERFORM pg_temp.ok((v_row->>'address') IS NOT DISTINCT FROM r.address, 'C4 address ' || r.id);
    PERFORM pg_temp.ok((v_row->>'latitude')::numeric IS NOT DISTINCT FROM r.latitude, 'C5 lat ' || r.id);
    PERFORM pg_temp.ok((v_row->>'longitude')::numeric IS NOT DISTINCT FROM r.longitude, 'C6 lng ' || r.id);
    PERFORM pg_temp.ok((v_row->>'iban') IS NOT DISTINCT FROM r.iban, 'C7 iban ' || r.id);
    PERFORM pg_temp.ok((v_row->>'bank_name') IS NOT DISTINCT FROM r.bank_name, 'C8 bank ' || r.id);
    PERFORM pg_temp.ok((v_row->>'account_holder_name') IS NOT DISTINCT FROM
      COALESCE(NULLIF(btrim(r.account_holder_name), ''), r.account_holder), 'C9 holder ' || r.id);
    PERFORM pg_temp.ok((v_row->'profiles'->>'phone') IS NOT DISTINCT FROM r.owner_phone, 'C10 owner phone ' || r.id);

    -- Eski anahtarlar yerinde
    PERFORM pg_temp.ok(v_row ? 'profiles' AND v_row ? 'product_count' AND v_row ? 'net_earnings'
      AND v_row ? 'category_name' AND v_row ? 'scheduled_orders_enabled'
      AND v_row ? 'courier_deduction' AND NOT v_row ? 'rn' AND NOT v_row ? 'is_overridden',
      'K1 anahtarlar ' || r.id);

    IF NULLIF(btrim(r.phone), '') IS NOT NULL THEN
      v_with_phone := v_with_phone + 1;
      IF v_probe_shop IS NULL AND length(regexp_replace(r.phone, '\D', '', 'g')) >= 7 THEN
        v_probe_shop := r.id;
        v_probe := right(r.phone, 6);
        v_owner := r.owner_id;
      END IF;
    END IF;
  END LOOP;

  -- ------------------------------------------------------- telefonla arama
  IF v_probe_shop IS NOT NULL THEN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM pg_temp.as_user(v_admin);
    v_found := public.admin_shops_page(v_probe, NULL, 'default', 100, 0);
    EXECUTE 'RESET ROLE';
    PERFORM pg_temp.ok(EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_found->'rows') e
       WHERE (e->>'id')::uuid = v_probe_shop), 'Q1 telefonla arama');

    -- ------------------------------------------------- admin_user_detail
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM pg_temp.as_user(v_admin);
    v_detail := public.admin_user_detail(v_owner);
    EXECUTE 'RESET ROLE';
    PERFORM pg_temp.ok((v_detail->>'shop_id')::uuid = v_probe_shop, 'U1 shop_id');
    PERFORM pg_temp.ok((v_detail->>'shop_phone') = (SELECT phone FROM public.shops WHERE id = v_probe_shop), 'U2 shop_phone');
    PERFORM pg_temp.ok(v_detail ? 'phone' AND v_detail ? 'shop_name', 'U3 eski anahtarlar');
  END IF;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.as_user(v_admin);
  v_detail := public.admin_user_detail(v_user);
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_detail->'shop_id' = 'null'::jsonb AND v_detail->'shop_phone' = 'null'::jsonb, 'U4 dükkansız NULL');

  RAISE EXCEPTION 'TESTS_PASSED checks=% shops=% with_phone=% probe=%',
    current_setting('t.n'), v_shop_count, v_with_phone, COALESCE(v_probe_shop::text, '-');
END
$test$;
