-- Görev 3.2 — satıcı öne çıkarma (sponsorlu vitrin) canlı doğrulaması.
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/seller_sponsorships_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası: DO bloğu RAISE EXCEPTION ile biter,
-- testin yazdığı her şey (bakiye, satın almalar, ayarlar) geri alınır.
DO $test$
DECLARE
  v_shop uuid;        -- satıcı A'nın yayındaki mağazası
  v_owner uuid;       -- satıcı A
  v_other_owner uuid; -- satıcı B (başka mağaza sahibi)
  v_other_product uuid;
  v_product uuid;
  v_pkg_list_day uuid;
  v_pkg_list_week uuid;
  v_pkg_cat_day uuid;
  v_pkg_pdisc_day uuid;
  v_pkg_pcat_week uuid;
  v_res jsonb;
  v_res2 jsonb;
  v_until timestamptz;
  v_balance numeric;
  v_hint text;
  v_state text;
  v_n integer;
  v_checks integer := 0;
BEGIN
  SELECT s.id, s.owner_id INTO v_shop, v_owner
    FROM public.shops s JOIN public.profiles p ON p.id = s.owner_id
   WHERE s.is_active AND s.is_approved AND COALESCE(p.role::text, '') <> 'admin'
     AND EXISTS (SELECT 1 FROM public.products pr WHERE pr.shop_id = s.id)
   ORDER BY s.created_at LIMIT 1;
  SELECT s.owner_id INTO v_other_owner
    FROM public.shops s JOIN public.profiles p ON p.id = s.owner_id
   WHERE s.owner_id <> v_owner AND COALESCE(p.role::text, '') <> 'admin'
   ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_product FROM public.products WHERE shop_id = v_shop ORDER BY created_at LIMIT 1;
  SELECT id INTO v_other_product FROM public.products WHERE shop_id <> v_shop ORDER BY created_at LIMIT 1;
  IF v_shop IS NULL OR v_other_owner IS NULL OR v_product IS NULL OR v_other_product IS NULL THEN
    RAISE EXCEPTION 'test verisi bulunamadı';
  END IF;

  SELECT id INTO v_pkg_list_day  FROM public.sponsorship_packages WHERE placement = 'shop_list' AND duration_days = 1;
  SELECT id INTO v_pkg_list_week FROM public.sponsorship_packages WHERE placement = 'shop_list' AND duration_days = 7;
  SELECT id INTO v_pkg_cat_day   FROM public.sponsorship_packages WHERE placement = 'shop_category' AND duration_days = 1;
  SELECT id INTO v_pkg_pdisc_day FROM public.sponsorship_packages WHERE placement = 'product_discount' AND duration_days = 1;
  SELECT id INTO v_pkg_pcat_week FROM public.sponsorship_packages WHERE placement = 'product_category' AND duration_days = 7;

  -- Temiz başlangıç (test bitince hepsi geri alınır)
  UPDATE public.app_settings SET value = '"true"' WHERE key = 'sponsorship_enabled';
  UPDATE public.app_settings SET value = '"false"' WHERE key = 'sponsorship_requires_approval';
  UPDATE public.products SET old_price = NULL, discount_price = NULL, is_available = true WHERE id = v_product;
  UPDATE public.user_balances SET balance = 0 WHERE user_id = v_owner;
  IF NOT FOUND THEN
    INSERT INTO public.user_balances (user_id, balance) VALUES (v_owner, 0);
  END IF;

  -- [1] yapı: işlem tipi, sütunlar, RLS, 8 varsayılan paket
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
     WHERE t.typname = 'balance_transaction_type' AND e.enumlabel = 'sponsorship_purchase'
  ) THEN RAISE EXCEPTION '[1] sponsorship_purchase işlem tipi yok'; END IF;
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema = 'public'
     AND ((table_name = 'shops' AND column_name IN ('sponsored_list_until', 'sponsored_category_until'))
       OR (table_name = 'products' AND column_name IN ('sponsored_category_until', 'sponsored_discount_until')));
  IF v_n <> 4 THEN RAISE EXCEPTION '[1] vitrin sütunları eksik: %', v_n; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.shop_sponsorships'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.sponsorship_packages'::regclass) THEN
    RAISE EXCEPTION '[1] RLS kapalı';
  END IF;
  SELECT count(*) INTO v_n FROM public.sponsorship_packages WHERE is_active;
  IF v_n < 8 THEN RAISE EXCEPTION '[1] varsayılan paketler eksik: %', v_n; END IF;
  v_checks := v_checks + 1;

  -- Satıcı A olarak
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);

  -- [2] koruma: istemci vitrin sütunlarını yazamaz (sessizce eski değer).
  -- Satır GERÇEKTEN güncellenir (RLS engellemez; updated_at işlem zamanına
  -- döner) ama vitrin sütunu eski değerinde kalır.
  UPDATE public.shops SET sponsored_list_until = now() + interval '1 year',
                          updated_at = now() - interval '1 day' WHERE id = v_shop;
  UPDATE public.products SET sponsored_discount_until = now() + interval '1 year',
                             sponsored_category_until = now() + interval '1 year' WHERE id = v_product;
  EXECUTE 'RESET ROLE';
  IF (SELECT updated_at FROM public.shops WHERE id = v_shop) IS DISTINCT FROM now()
     OR (SELECT updated_at FROM public.products WHERE id = v_product) IS DISTINCT FROM now() THEN
    RAISE EXCEPTION '[2] satıcının güncellemesi satıra hiç ulaşmadı (RLS?) — koruma sınanamadı';
  END IF;
  IF (SELECT sponsored_list_until FROM public.shops WHERE id = v_shop) IS NOT NULL
     OR (SELECT sponsored_discount_until FROM public.products WHERE id = v_product) IS NOT NULL
     OR (SELECT sponsored_category_until FROM public.products WHERE id = v_product) IS NOT NULL THEN
    RAISE EXCEPTION '[2] istemci vitrin sütununu yazabildi';
  END IF;
  -- Yönetici/bakım bağlamı (postgres) yazabilir: koruma yalnız istemci rollerine
  UPDATE public.shops SET sponsored_list_until = now() + interval '1 hour' WHERE id = v_shop;
  IF (SELECT sponsored_list_until FROM public.shops WHERE id = v_shop) IS NULL THEN
    RAISE EXCEPTION '[2] sunucu bağlamı yazamadı';
  END IF;
  UPDATE public.shops SET sponsored_list_until = NULL WHERE id = v_shop;
  v_checks := v_checks + 1;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);

  -- [3] yetersiz bakiye
  BEGIN
    PERFORM public.purchase_shop_sponsorship(v_shop, v_pkg_list_day);
    RAISE EXCEPTION '[3] bakiyesiz satın alındı';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    IF v_hint IS DISTINCT FROM 'insufficient_balance' THEN RAISE EXCEPTION '[3] ipucu: %', v_hint; END IF;
  END;
  v_checks := v_checks + 1;

  -- [4] satın alma: bakiye düşer, işlem kaydı, vitrin sütunu
  EXECUTE 'RESET ROLE';
  UPDATE public.user_balances SET balance = 1000 WHERE user_id = v_owner;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_res := public.purchase_shop_sponsorship(v_shop, v_pkg_list_day);
  EXECUTE 'RESET ROLE';
  IF v_res ->> 'status' <> 'active' OR (v_res ->> 'price')::numeric <> 30 THEN
    RAISE EXCEPTION '[4] dönüş: %', v_res;
  END IF;
  IF abs(extract(epoch FROM ((v_res ->> 'ends_at')::timestamptz - (v_res ->> 'starts_at')::timestamptz)) - 86400) > 1 THEN
    RAISE EXCEPTION '[4] süre 1 gün değil: %', v_res;
  END IF;
  SELECT balance INTO v_balance FROM public.user_balances WHERE user_id = v_owner;
  IF v_balance <> 970 THEN RAISE EXCEPTION '[4] bakiye %', v_balance; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.balance_transactions t
     WHERE t.user_id = v_owner AND t.type = 'sponsorship_purchase' AND t.amount = 30
       AND t.reference_type = 'shop_sponsorship' AND t.reference_id = (v_res ->> 'id')::uuid
       AND t.balance_before = 1000 AND t.balance_after = 970
  ) THEN RAISE EXCEPTION '[4] işlem kaydı yok'; END IF;
  SELECT sponsored_list_until INTO v_until FROM public.shops WHERE id = v_shop;
  IF v_until IS DISTINCT FROM (v_res ->> 'ends_at')::timestamptz THEN
    RAISE EXCEPTION '[4] vitrin sütunu % ≠ %', v_until, v_res ->> 'ends_at';
  END IF;
  v_checks := v_checks + 1;

  -- [5] zincir: ikinci satın alma öncekinin bitişinden başlar
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_res2 := public.purchase_shop_sponsorship(v_shop, v_pkg_list_week);
  EXECUTE 'RESET ROLE';
  IF (v_res2 ->> 'starts_at')::timestamptz IS DISTINCT FROM (v_res ->> 'ends_at')::timestamptz THEN
    RAISE EXCEPTION '[5] zincir kopuk: % sonra %', v_res ->> 'ends_at', v_res2 ->> 'starts_at';
  END IF;
  IF (SELECT sponsored_list_until FROM public.shops WHERE id = v_shop) IS DISTINCT FROM (v_res2 ->> 'ends_at')::timestamptz THEN
    RAISE EXCEPTION '[5] vitrin sütunu zincir sonunu tutmuyor';
  END IF;
  IF (SELECT balance FROM public.user_balances WHERE user_id = v_owner) <> 820 THEN
    RAISE EXCEPTION '[5] bakiye 820 değil';
  END IF;
  v_checks := v_checks + 1;

  -- [6] ürün vitrinleri: indirimsiz ürün İndirimdekiler'e çıkamaz; indirimliyse çıkar
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.purchase_shop_sponsorship(v_shop, v_pkg_pdisc_day, v_product);
    RAISE EXCEPTION '[6] indirimsiz ürün kabul edildi';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    IF v_hint IS DISTINCT FROM 'product_not_discounted' THEN RAISE EXCEPTION '[6] ipucu: %', v_hint; END IF;
  END;
  EXECUTE 'RESET ROLE';
  UPDATE public.products SET old_price = price + 10 WHERE id = v_product;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_res := public.purchase_shop_sponsorship(v_shop, v_pkg_pdisc_day, v_product);
  v_res2 := public.purchase_shop_sponsorship(v_shop, v_pkg_pcat_week, v_product);
  EXECUTE 'RESET ROLE';
  IF (SELECT sponsored_discount_until FROM public.products WHERE id = v_product) IS DISTINCT FROM (v_res ->> 'ends_at')::timestamptz
     OR (SELECT sponsored_category_until FROM public.products WHERE id = v_product) IS DISTINCT FROM (v_res2 ->> 'ends_at')::timestamptz THEN
    RAISE EXCEPTION '[6] ürün vitrin sütunları yanlış';
  END IF;
  v_checks := v_checks + 1;

  -- [7] hedef/vitrin uyumu
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.purchase_shop_sponsorship(v_shop, v_pkg_list_day, v_product);
    RAISE EXCEPTION '[7] mağaza vitrinine ürün kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.purchase_shop_sponsorship(v_shop, v_pkg_pdisc_day);
    RAISE EXCEPTION '[7] ürünsüz ürün vitrini kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.purchase_shop_sponsorship(v_shop, v_pkg_pcat_week, v_other_product);
    RAISE EXCEPTION '[7] başka mağazanın ürünü kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- [8] başkasının mağazası için satın alınamaz
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other_owner, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.purchase_shop_sponsorship(v_shop, v_pkg_list_day);
    RAISE EXCEPTION '[8] başkasının mağazası kabul edildi';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  -- [8b] B, A'nın satın almalarını göremez; A kendininkileri görür
  SELECT count(*) INTO v_n FROM public.shop_sponsorships WHERE shop_id = v_shop;
  IF v_n <> 0 THEN RAISE EXCEPTION '[8] B, A''nın satın almalarını görüyor: %', v_n; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_n FROM public.shop_sponsorships WHERE shop_id = v_shop;
  IF v_n < 4 THEN RAISE EXCEPTION '[8] A kendi satın almalarını görmüyor: %', v_n; END IF;
  -- doğrudan yazamaz
  BEGIN
    INSERT INTO public.shop_sponsorships (shop_id, placement, package_name, duration_days, price_paid, status, starts_at, ends_at)
    VALUES (v_shop, 'shop_list', 'bedava', 90, 0, 'active', now(), now() + interval '90 days');
    RAISE EXCEPTION '[8] doğrudan satır yazıldı';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'RESET ROLE';
  v_checks := v_checks + 1;

  -- [9] onay modu: ücret alınır, vitrin değişmez
  UPDATE public.app_settings SET value = '"true"' WHERE key = 'sponsorship_requires_approval';
  SELECT balance INTO v_balance FROM public.user_balances WHERE user_id = v_owner;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_res := public.purchase_shop_sponsorship(v_shop, v_pkg_cat_day);
  EXECUTE 'RESET ROLE';
  IF v_res ->> 'status' <> 'pending' OR v_res ->> 'starts_at' IS NOT NULL THEN
    RAISE EXCEPTION '[9] onay modu dönüşü: %', v_res;
  END IF;
  IF (SELECT sponsored_category_until FROM public.shops WHERE id = v_shop) IS NOT NULL THEN
    RAISE EXCEPTION '[9] onaysız vitrine çıktı';
  END IF;
  IF (SELECT balance FROM public.user_balances WHERE user_id = v_owner) <> v_balance - 20 THEN
    RAISE EXCEPTION '[9] onay modunda ücret alınmadı';
  END IF;
  UPDATE public.app_settings SET value = '"false"' WHERE key = 'sponsorship_requires_approval';
  v_checks := v_checks + 1;

  -- [10] özellik kapalı
  UPDATE public.app_settings SET value = '"false"' WHERE key = 'sponsorship_enabled';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.purchase_shop_sponsorship(v_shop, v_pkg_list_day);
    RAISE EXCEPTION '[10] kapalıyken satın alındı';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    IF v_hint IS DISTINCT FROM 'disabled' THEN RAISE EXCEPTION '[10] ipucu: %', v_hint; END IF;
  END;
  EXECUTE 'RESET ROLE';
  UPDATE public.app_settings SET value = '"true"' WHERE key = 'sponsorship_enabled';
  v_checks := v_checks + 1;

  -- [11] yayında olmayan mağaza
  UPDATE public.shops SET is_approved = false WHERE id = v_shop;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.purchase_shop_sponsorship(v_shop, v_pkg_list_day);
    RAISE EXCEPTION '[11] onaysız mağaza satın aldı';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    IF v_hint IS DISTINCT FROM 'shop_not_listed' THEN RAISE EXCEPTION '[11] ipucu: %', v_hint; END IF;
  END;
  EXECUTE 'RESET ROLE';
  UPDATE public.shops SET is_approved = true WHERE id = v_shop;
  v_checks := v_checks + 1;

  -- [12] paketler: satıcı yalnız aktifleri görür; anon hiç göremez
  UPDATE public.sponsorship_packages SET is_active = false WHERE id = v_pkg_list_week;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_n FROM public.sponsorship_packages WHERE id = v_pkg_list_week;
  EXECUTE 'RESET ROLE';
  IF v_n <> 0 THEN RAISE EXCEPTION '[12] pasif paket görünüyor'; END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  BEGIN
    SELECT count(*) INTO v_n FROM public.sponsorship_packages;
    RAISE EXCEPTION '[12] anon paketleri okudu';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'RESET ROLE';
  IF has_function_privilege('anon', 'public.purchase_shop_sponsorship(uuid, uuid, uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.purchase_shop_sponsorship(uuid, uuid, uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '[12] RPC yetkileri yanlış';
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
