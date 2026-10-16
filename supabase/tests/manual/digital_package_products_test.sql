-- Dijital "Paket" satış şekli canlı doğrulaması
-- (20261016000001_digital_package_products.sql). Kendini geri alır.
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/digital_package_products_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası (DO bloğu RAISE EXCEPTION ile biter,
-- böylece testin eklediği ürün/sipariş/bakiye/bildirim değişiklikleri geri alınır).
DO $test$
DECLARE
  v_shop      uuid;
  v_seller    uuid;
  v_buyer     uuid;
  v_other     uuid;
  v_provider  uuid;
  v_pkg       uuid;
  v_smm       uuid;
  v_res       jsonb;
  v_res2      jsonb;
  v_order_a   uuid;
  v_order_b   uuid;
  v_bal0      numeric;
  v_bal       numeric;
  v_seller_b0 numeric;
  v_seller_b  numeric;
  v_n         integer;
  v_row       public.digital_orders%ROWTYPE;
  v_prod      public.products%ROWTYPE;
  v_checks    integer := 0;
BEGIN
  SELECT s.id, s.owner_id INTO v_shop, v_seller
    FROM public.shops s WHERE s.owner_id IS NOT NULL
   ORDER BY s.created_at LIMIT 1;
  SELECT b.user_id INTO v_buyer
    FROM public.user_balances b WHERE b.user_id <> v_seller
   ORDER BY b.created_at LIMIT 1;
  SELECT p.id INTO v_other
    FROM public.profiles p
   WHERE p.id NOT IN (v_seller, v_buyer) AND p.role::text <> 'admin'
     AND NOT EXISTS (SELECT 1 FROM public.shops s WHERE s.owner_id = p.id)
   LIMIT 1;
  SELECT sp.id INTO v_provider FROM public.smm_providers sp LIMIT 1;
  IF v_shop IS NULL OR v_buyer IS NULL OR v_other IS NULL OR v_provider IS NULL THEN
    RAISE EXCEPTION '[0] test verisi bulunamadı';
  END IF;
  UPDATE public.user_balances SET balance = 1000 WHERE user_id = v_buyer;
  INSERT INTO public.user_balances(user_id) VALUES (v_seller) ON CONFLICT (user_id) DO NOTHING;
  SELECT balance INTO v_seller_b0 FROM public.user_balances WHERE user_id = v_seller;

  -- [1] paket ürün: sağlayıcı alanları tetikleyiciyle temizlenir
  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, product_type,
      digital_mode, is_available, smm_provider_id, smm_service_id, price_per_1000,
      min_quantity, max_quantity, max_orders_per_user)
  VALUES (v_shop, 'TEST 1000 Takipçi Paketi', 'test-paket-' || substr(md5(random()::text), 1, 8),
      49.90, 0, 'digital', 'package', true, v_provider, '123', 12.5, 10, 5000, 2)
  RETURNING * INTO v_prod;
  v_pkg := v_prod.id;
  IF v_prod.smm_provider_id IS NOT NULL OR v_prod.smm_service_id IS NOT NULL
     OR v_prod.price_per_1000 IS NOT NULL OR v_prod.min_quantity IS NOT NULL THEN
    RAISE EXCEPTION '[1] paket satırında sağlayıcı alanı kaldı: %', row_to_json(v_prod);
  END IF;
  v_checks := v_checks + 1;

  -- [2] kısıtlar: fiyatsız paket ve sağlayıcısız SMM reddedilir; fiziksel ürün smm'e çekilir
  BEGIN
    INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, product_type, digital_mode)
    VALUES (v_shop, 'TEST bedava paket', 'test-bedava-' || substr(md5(random()::text), 1, 8), 0, 0, 'digital', 'package');
    RAISE EXCEPTION '[2] fiyatsız paket eklendi';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, product_type)
    VALUES (v_shop, 'TEST sağlayıcısız smm', 'test-smm0-' || substr(md5(random()::text), 1, 8), 5, 0, 'digital');
    RAISE EXCEPTION '[2] sağlayıcısız SMM ürünü eklendi';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, digital_mode)
  VALUES (v_shop, 'TEST fiziksel', 'test-fiz-' || substr(md5(random()::text), 1, 8), 5, 1, 'package')
  RETURNING * INTO v_prod;
  IF v_prod.digital_mode <> 'smm' THEN RAISE EXCEPTION '[2] fiziksel üründe digital_mode=%', v_prod.digital_mode; END IF;
  v_checks := v_checks + 1;

  -- [3] SMM → paket dönüşümü sağlayıcı alanlarını temizler
  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, product_type,
      is_available, smm_provider_id, smm_service_id, price_per_1000, min_quantity, max_quantity)
  VALUES (v_shop, 'TEST SMM', 'test-smm-' || substr(md5(random()::text), 1, 8), 12, 0, 'digital',
      true, v_provider, '999', 12, 100, 1000)
  RETURNING id INTO v_smm;
  UPDATE public.products SET digital_mode = 'package', price = 30 WHERE id = v_smm
  RETURNING * INTO v_prod;
  IF v_prod.smm_provider_id IS NOT NULL OR v_prod.max_quantity IS NOT NULL THEN
    RAISE EXCEPTION '[3] dönüşümde sağlayıcı alanı kaldı';
  END IF;
  v_checks := v_checks + 1;

  -- Sipariş RPC'leri service_role ister
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  SELECT balance INTO v_bal0 FROM public.user_balances WHERE user_id = v_buyer;

  -- [4] pakette adet 1 dışı reddedilir
  BEGIN
    PERFORM public.create_digital_order_with_points(v_buyer, v_pkg, 'https://instagram.com/test', 2,
      'test-pkg-qty2-' || substr(md5(random()::text), 1, 8), false);
    RAISE EXCEPTION '[4] adet 2 kabul edildi';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- [5] adet 1: sabit fiyat düşer, sağlayıcısız manuel sipariş açılır
  v_res := public.create_digital_order_with_points(v_buyer, v_pkg, 'https://instagram.com/test', 1,
    'test-pkg-a-0001', false);
  v_order_a := (v_res ->> 'digital_order_id')::uuid;
  IF v_res ->> 'delivery_mode' <> 'manual' OR v_res ->> 'provider_id' IS NOT NULL
     OR (v_res ->> 'gross_total_try')::numeric <> 49.90 OR (v_res ->> 'cash_paid_try')::numeric <> 49.90
     OR (v_res ->> 'duplicate')::boolean THEN
    RAISE EXCEPTION '[5] RPC yanıtı: %', v_res;
  END IF;
  SELECT * INTO v_row FROM public.digital_orders WHERE id = v_order_a;
  IF v_row.delivery_mode <> 'manual' OR v_row.provider_id IS NOT NULL OR v_row.quantity <> 1
     OR v_row.unit_price <> 49.90 OR v_row.total_price <> 49.90
     OR v_row.reconciliation_status <> 'not_required' OR v_row.status::text <> 'pending' THEN
    RAISE EXCEPTION '[5] sipariş satırı: %', row_to_json(v_row);
  END IF;
  SELECT balance INTO v_bal FROM public.user_balances WHERE user_id = v_buyer;
  IF v_bal <> v_bal0 - 49.90 THEN RAISE EXCEPTION '[5] bakiye % → %', v_bal0, v_bal; END IF;
  v_checks := v_checks + 1;

  -- [6] satıcıya "teslim bekliyor" bildirimi
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE user_id = v_seller AND type = 'seller_new_digital_order' AND entity_id = v_order_a::text;
  IF v_n <> 1 THEN RAISE EXCEPTION '[6] satıcı bildirimi sayısı %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [7] aynı anahtarla tekrar: çift çekim yok, duplicate + manual döner
  v_res2 := public.create_digital_order_with_points(v_buyer, v_pkg, 'https://instagram.com/test', 1,
    'test-pkg-a-0001', false);
  SELECT balance INTO v_bal FROM public.user_balances WHERE user_id = v_buyer;
  IF NOT (v_res2 ->> 'duplicate')::boolean OR v_res2 ->> 'delivery_mode' <> 'manual'
     OR (v_res2 ->> 'digital_order_id')::uuid <> v_order_a OR v_bal <> v_bal0 - 49.90 THEN
    RAISE EXCEPTION '[7] tekrar: % bakiye %', v_res2, v_bal;
  END IF;
  v_checks := v_checks + 1;

  -- [8] RLS: satıcı manuel siparişi görür, ilgisiz kullanıcı görmez
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_seller, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO v_n FROM public.digital_orders WHERE id = v_order_a;
  PERFORM set_config('role', 'postgres', true);
  IF v_n <> 1 THEN RAISE EXCEPTION '[8] satıcı göremedi'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO v_n FROM public.digital_orders WHERE id = v_order_a;
  PERFORM set_config('role', 'postgres', true);
  IF v_n <> 0 THEN RAISE EXCEPTION '[8] ilgisiz kullanıcı gördü'; END IF;
  v_checks := v_checks + 1;

  -- [9] teslim: smm-order-manual-status'un 'completed' sırası → satıcıya net, alıcıya bildirim
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  PERFORM public.set_digital_order_reconciliation(v_order_a, 'settled');
  PERFORM public.credit_digital_order_seller(v_order_a, 1);
  UPDATE public.digital_orders SET status = 'completed' WHERE id = v_order_a;
  SELECT * INTO v_row FROM public.digital_orders WHERE id = v_order_a;
  SELECT balance INTO v_seller_b FROM public.user_balances WHERE user_id = v_seller;
  IF NOT v_row.seller_credited OR v_row.net_seller_amount IS NULL
     OR v_seller_b <> v_seller_b0 + v_row.net_seller_amount THEN
    RAISE EXCEPTION '[9] satıcı kredisi: % bakiye % → %', row_to_json(v_row), v_seller_b0, v_seller_b;
  END IF;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE user_id = v_buyer AND type = 'digital_order_status' AND entity_id = v_order_a::text
     AND title = 'Paketiniz teslim edildi';
  IF v_n <> 1 THEN RAISE EXCEPTION '[9] alıcı teslim bildirimi %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [10] iptal: tam iade, alıcıya iptal bildirimi
  v_res := public.create_digital_order_with_points(v_buyer, v_pkg, 'https://instagram.com/test2', 1,
    'test-pkg-b-0001', false);
  v_order_b := (v_res ->> 'digital_order_id')::uuid;
  PERFORM public.refund_digital_order_payment(v_order_b, 49.90, 'test-refund-' || v_order_b, 'Test iptal', true);
  UPDATE public.digital_orders SET status = 'canceled' WHERE id = v_order_b;
  SELECT balance INTO v_bal FROM public.user_balances WHERE user_id = v_buyer;
  IF v_bal <> v_bal0 - 49.90 THEN RAISE EXCEPTION '[10] iade sonrası bakiye %', v_bal; END IF;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE user_id = v_buyer AND type = 'digital_order_status' AND entity_id = v_order_b::text
     AND title = 'Paket siparişiniz iptal edildi';
  IF v_n <> 1 THEN RAISE EXCEPTION '[10] alıcı iptal bildirimi %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [11] kullanıcı başı limit (2) pakette de geçerli: iptal edilen de sayılır
  BEGIN
    PERFORM public.create_digital_order_with_points(v_buyer, v_pkg, 'https://instagram.com/test3', 1,
      'test-pkg-c-0001', false);
    RAISE EXCEPTION '[11] limit aşıldı';
  EXCEPTION WHEN SQLSTATE '54000' THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- [12] eski puansız RPC istemciye kapalı; yeni RPC yalnız service_role
  IF has_function_privilege('authenticated', 'public.create_digital_order(uuid,uuid,text,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '[12] eski create_digital_order açık';
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_buyer, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.create_digital_order_with_points(v_buyer, v_pkg, 'https://x.test', 1, 'test-pkg-d-0001', false);
    RAISE EXCEPTION '[12] authenticated rezervasyon yaptı';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- [13] SMM siparişi değişmedi: sağlayıcılı, provider modunda, pending_provider
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, product_type,
      is_available, smm_provider_id, smm_service_id, price_per_1000, min_quantity, max_quantity)
  VALUES (v_shop, 'TEST SMM 2', 'test-smm2-' || substr(md5(random()::text), 1, 8), 10, 0, 'digital',
      true, v_provider, '777', 10, 100, 10000)
  RETURNING id INTO v_smm;
  v_res := public.create_digital_order_with_points(v_buyer, v_smm, 'https://instagram.com/smm', 1500,
    'test-smm-a-0001', false);
  SELECT * INTO v_row FROM public.digital_orders WHERE id = (v_res ->> 'digital_order_id')::uuid;
  IF v_res ->> 'delivery_mode' <> 'provider' OR (v_res ->> 'provider_id')::uuid <> v_provider
     OR v_res ->> 'smm_service_id' <> '777' OR v_row.reconciliation_status <> 'pending_provider'
     OR v_row.total_price <> 15.00 THEN
    RAISE EXCEPTION '[13] SMM yanıtı: % / %', v_res, row_to_json(v_row);
  END IF;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE type IN ('seller_new_digital_order', 'digital_order_status') AND entity_id = v_row.id::text;
  IF v_n <> 0 THEN RAISE EXCEPTION '[13] SMM siparişine manuel bildirim gitti'; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END;
$test$;
