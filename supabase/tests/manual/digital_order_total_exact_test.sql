-- Dijital (SMM) sipariş toplamı canlı doğrulaması
-- (20261016000011_digital_order_total_exact_per_thousand.sql). Kendini geri alır.
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/digital_order_total_exact_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası (DO bloğu RAISE EXCEPTION ile biter,
-- böylece testin eklediği ürün/sipariş/bakiye değişiklikleri geri alınır).
DO $test$
DECLARE
  v_shop      uuid;
  v_seller    uuid;
  v_buyer     uuid;
  v_provider  uuid;
  v_prod      uuid;
  v_res       jsonb;
  v_row       public.digital_orders%ROWTYPE;
  v_bal0      numeric;
  v_bal       numeric;
  v_case      record;
  v_i         integer := 0;
  v_checks    integer := 0;
BEGIN
  SELECT s.id, s.owner_id INTO v_shop, v_seller
    FROM public.shops s WHERE s.owner_id IS NOT NULL
   ORDER BY s.created_at LIMIT 1;
  SELECT b.user_id INTO v_buyer
    FROM public.user_balances b WHERE b.user_id <> v_seller
   ORDER BY b.created_at LIMIT 1;
  SELECT sp.id INTO v_provider FROM public.smm_providers sp LIMIT 1;
  IF v_shop IS NULL OR v_buyer IS NULL OR v_provider IS NULL THEN
    RAISE EXCEPTION '[0] test verisi bulunamadı';
  END IF;
  UPDATE public.user_balances SET balance = 100000 WHERE user_id = v_buyer;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);

  -- (1000 adet fiyatı, adet, beklenen toplam). İlk satır kullanıcının bildirdiği
  -- durum: eskiden birim 0,0002'ye kırpılıp 0,20 TL çıkıyordu.
  FOR v_case IN
    SELECT * FROM (VALUES
      (0.24::numeric, 1000, 0.24::numeric),
      (0.24, 100000, 24.00),
      (0.35, 10000, 3.50),
      (0.67, 100, 0.07),
      (1.99, 333, 0.66),
      (45.55, 1234, 56.21),
      (10, 1500, 15.00)
    ) AS t(ppk, qty, expected)
  LOOP
    v_i := v_i + 1;
    INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, product_type,
        is_available, smm_provider_id, smm_service_id, price_per_1000, min_quantity, max_quantity)
    VALUES (v_shop, 'TEST SMM toplam ' || v_i, 'test-smm-tot-' || substr(md5(random()::text), 1, 8),
        v_case.ppk, 0, 'digital', true, v_provider, '900' || v_i, v_case.ppk, 1, 1000000)
    RETURNING id INTO v_prod;

    SELECT balance INTO v_bal0 FROM public.user_balances WHERE user_id = v_buyer;
    v_res := public.create_digital_order_with_points(v_buyer, v_prod, 'https://instagram.com/t',
      v_case.qty, 'test-smm-total-' || v_i || '-' || substr(md5(random()::text), 1, 8), false);
    SELECT * INTO v_row FROM public.digital_orders WHERE id = (v_res ->> 'digital_order_id')::uuid;
    SELECT balance INTO v_bal FROM public.user_balances WHERE user_id = v_buyer;

    IF v_row.gross_total_try <> v_case.expected OR v_row.total_price <> v_case.expected
       OR (v_res ->> 'gross_total_try')::numeric <> v_case.expected THEN
      RAISE EXCEPTION '[%] ppk=% adet=%: beklenen %, sunucu % (yanıt %)',
        v_i, v_case.ppk, v_case.qty, v_case.expected, v_row.gross_total_try, v_res;
    END IF;
    IF v_bal0 - v_bal <> v_case.expected THEN
      RAISE EXCEPTION '[%] bakiyeden % düştü, beklenen %', v_i, v_bal0 - v_bal, v_case.expected;
    END IF;
    IF v_row.unit_price <> v_case.ppk / 1000.0
       OR v_row.total_price <> round(v_row.unit_price * v_row.quantity, 2) THEN
      RAISE EXCEPTION '[%] birim kaydı: % (beklenen %)', v_i, v_row.unit_price, v_case.ppk / 1000.0;
    END IF;
    v_checks := v_checks + 1;
  END LOOP;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END;
$test$;
