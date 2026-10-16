-- Canlı doğrulama: sınırsız stok + stok tükendi bildirimi
-- (20261016000005_products_unlimited_stock.sql).
--
-- Tek DO bloğu; sonundaki RAISE EXCEPTION her şeyi geri alır. Çalıştırma:
--   npx supabase db query --linked --file supabase/tests/manual/products_unlimited_stock_test.sql
-- Beklenen çıktı: "TESTS_PASSED ..." (FAIL satırı yoksa hepsi geçti).

DO $$
DECLARE
  v_log text := '';
  v_fail int := 0;
  v_shop uuid;
  v_owner uuid;
  v_unl uuid;
  v_lim uuid;
  v_dig uuid;
  v_order uuid;
  v_order2 uuid;
  r record;
  v_cnt int;
BEGIN
  SELECT id, owner_id INTO v_shop, v_owner FROM public.shops WHERE owner_id IS NOT NULL LIMIT 1;

  CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_name text, INOUT p_log text, INOUT p_fail int)
  LANGUAGE plpgsql AS $f$
  BEGIN
    IF COALESCE(p_cond, false) THEN p_log := p_log || E'\nok   ' || p_name;
    ELSE p_log := p_log || E'\nFAIL ' || p_name; p_fail := p_fail + 1; END IF;
  END $f$;

  -- 1) NULL stok → sınırsız
  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity)
  VALUES (v_shop, 'TEST sınırsız', 'test-sinirsiz-' || gen_random_uuid(), 10, NULL)
  RETURNING id INTO v_unl;
  SELECT stock_unlimited, stock_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.stock_unlimited AND r.stock_quantity = 999999, 'insert NULL -> unlimited 999999', v_log, v_fail);

  -- 2) Eski istemci 999999'u geri yazar → sınırsız kalır
  UPDATE public.products SET stock_quantity = 999999, name = 'TEST sınırsız 2' WHERE id = v_unl;
  SELECT stock_unlimited, stock_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.stock_unlimited AND r.stock_quantity = 999999, 'resave sentinel keeps unlimited', v_log, v_fail);

  -- 3) Sınırsız stoğa gerçek değer → takipli
  UPDATE public.products SET stock_quantity = 7 WHERE id = v_unl;
  SELECT stock_unlimited, stock_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(NOT r.stock_unlimited AND r.stock_quantity = 7, 'explicit stock turns unlimited off', v_log, v_fail);

  -- 4) Yeniden boş → tekrar sınırsız
  UPDATE public.products SET stock_quantity = NULL WHERE id = v_unl;
  SELECT stock_unlimited, stock_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.stock_unlimited AND r.stock_quantity = 999999, 'NULL again -> unlimited', v_log, v_fail);

  -- 5) Dijital ürün stok mantığına girmez
  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, product_type, digital_mode)
  VALUES (v_shop, 'TEST dijital', 'test-dijital-' || gen_random_uuid(), 50, NULL, 'digital', 'package')
  RETURNING id INTO v_dig;
  SELECT stock_unlimited, stock_quantity INTO r FROM public.products WHERE id = v_dig;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(NOT r.stock_unlimited AND r.stock_quantity = 0, 'digital -> not unlimited, 0', v_log, v_fail);

  -- 6) Takipli ürün (stok 2)
  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity)
  VALUES (v_shop, 'TEST takipli', 'test-takipli-' || gen_random_uuid(), 10, 2)
  RETURNING id INTO v_lim;

  -- Sipariş: sınırsızdan 2 (en fazla), takipliden 2
  INSERT INTO public.orders (order_number, shop_id, delivery_address_text, payment_method, subtotal, total)
  VALUES ('TEST-' || floor(random() * 1e9)::text, v_shop, 'test', 'cash', 70, 70)
  RETURNING id INTO v_order;
  INSERT INTO public.order_items (order_id, product_id, product_name, product_price, quantity, subtotal, price)
  VALUES (v_order, v_unl, 'TEST sınırsız', 10, 2, 20, 10),
         (v_order, v_lim, 'TEST takipli', 10, 2, 20, 10);

  UPDATE public.orders SET status = 'confirmed' WHERE id = v_order;

  SELECT stock_unlimited, stock_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.stock_unlimited AND r.stock_quantity = 999999, 'confirm leaves unlimited untouched', v_log, v_fail);
  SELECT stock_unlimited, stock_quantity INTO r FROM public.products WHERE id = v_lim;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(NOT r.stock_unlimited AND r.stock_quantity = 0, 'confirm decrements limited to 0', v_log, v_fail);

  SELECT count(*) INTO v_cnt FROM public.notifications
   WHERE user_id = v_owner AND type = 'seller_product_out_of_stock' AND entity_id = v_lim::text;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(v_cnt = 1, 'seller got 1 out-of-stock notification', v_log, v_fail);
  SELECT count(*) INTO v_cnt FROM public.notifications
   WHERE type = 'seller_product_out_of_stock' AND entity_id = v_unl::text;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(v_cnt = 0, 'no notification for unlimited', v_log, v_fail);

  -- 7) İptal: takipli geri yüklenir, sınırsız değişmez
  UPDATE public.orders SET status = 'cancelled' WHERE id = v_order;
  SELECT stock_unlimited, stock_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.stock_unlimited AND r.stock_quantity = 999999, 'cancel leaves unlimited untouched', v_log, v_fail);
  SELECT stock_quantity INTO r FROM public.products WHERE id = v_lim;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.stock_quantity = 2, 'cancel restores limited to 2', v_log, v_fail);

  -- 8) Stok yetmiyorsa onay reddedilir (eski davranış korunuyor)
  INSERT INTO public.orders (order_number, shop_id, delivery_address_text, payment_method, subtotal, total)
  VALUES ('TEST-' || floor(random() * 1e9)::text, v_shop, 'test', 'cash', 30, 30)
  RETURNING id INTO v_order2;
  INSERT INTO public.order_items (order_id, product_id, product_name, product_price, quantity, subtotal, price)
  VALUES (v_order2, v_lim, 'TEST takipli', 10, 3, 30, 10);
  BEGIN
    UPDATE public.orders SET status = 'confirmed' WHERE id = v_order2;
    SELECT * INTO v_log, v_fail FROM pg_temp.ok(false, 'insufficient stock rejected', v_log, v_fail);
  EXCEPTION WHEN OTHERS THEN
    SELECT * INTO v_log, v_fail FROM pg_temp.ok(SQLERRM LIKE 'Yetersiz stok%', 'insufficient stock rejected', v_log, v_fail);
  END;

  -- 9) Sınırsız stokta sipariş başına en fazla 2 adet (20261016000006)
  SELECT max_order_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.max_order_quantity = 2, 'unlimited -> max 2', v_log, v_fail);
  UPDATE public.products SET max_order_quantity = 5, min_order_quantity = 3 WHERE id = v_unl;
  SELECT min_order_quantity, max_order_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.max_order_quantity = 2 AND r.min_order_quantity = 2, 'unlimited clamps max 5 -> 2, min 3 -> 2', v_log, v_fail);
  UPDATE public.products SET max_order_quantity = 1, min_order_quantity = NULL WHERE id = v_unl;
  SELECT max_order_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.max_order_quantity = 1, 'unlimited keeps smaller seller max 1', v_log, v_fail);
  UPDATE public.products SET max_order_quantity = NULL WHERE id = v_unl;

  BEGIN
    INSERT INTO public.order_items (order_id, product_id, product_name, product_price, quantity, subtotal, price)
    VALUES (v_order2, v_unl, 'TEST sınırsız', 10, 3, 30, 10);
    SELECT * INTO v_log, v_fail FROM pg_temp.ok(false, 'unlimited order of 3 rejected', v_log, v_fail);
  EXCEPTION WHEN OTHERS THEN
    SELECT * INTO v_log, v_fail FROM pg_temp.ok(SQLERRM LIKE '%en fazla 2 adet%', 'unlimited order of 3 rejected', v_log, v_fail);
  END;

  -- 10) Stok girilince 2 sınırı kalkar (müşteri stok kadar alır)
  UPDATE public.products SET stock_quantity = 10 WHERE id = v_unl;
  SELECT stock_unlimited, max_order_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(NOT r.stock_unlimited AND r.max_order_quantity IS NULL, 'limited again -> max 2 removed', v_log, v_fail);

  -- 11) Satıcı aynı kayıtta farklı sınır yazdıysa korunur
  UPDATE public.products SET stock_quantity = NULL WHERE id = v_unl;
  UPDATE public.products SET stock_quantity = 10, max_order_quantity = 4 WHERE id = v_unl;
  SELECT max_order_quantity INTO r FROM public.products WHERE id = v_unl;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.max_order_quantity = 4, 'explicit max kept when leaving unlimited', v_log, v_fail);

  -- 12) Takipli üründe 2 sınırı yok
  SELECT max_order_quantity INTO r FROM public.products WHERE id = v_lim;
  SELECT * INTO v_log, v_fail FROM pg_temp.ok(r.max_order_quantity IS NULL, 'limited product has no max', v_log, v_fail);

  RAISE EXCEPTION 'TESTS_% (fail=%)%', CASE WHEN v_fail = 0 THEN 'PASSED' ELSE 'FAILED' END, v_fail, v_log;
END $$;
