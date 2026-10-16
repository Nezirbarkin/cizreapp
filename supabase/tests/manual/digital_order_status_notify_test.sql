-- Dijital sipariş durum/kazanç bildirimleri canlı doğrulaması
-- (20261016000002_digital_order_status_notify_all_modes.sql). Kendini geri alır.
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/digital_order_status_notify_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası (DO bloğu RAISE EXCEPTION ile biter,
-- böylece testin eklediği ürün/sipariş/bakiye/bildirim değişiklikleri geri alınır).
--
-- Edge Function'ların RPC sırası taklit edilir: önce ekonomik adım
-- (refund_digital_order_payment / set_digital_order_reconciliation +
-- credit_digital_order_seller), sonra durum yazımı.
DO $test$
DECLARE
  v_shop     uuid;
  v_seller   uuid;
  v_buyer    uuid;
  v_provider uuid;
  v_smm      uuid;
  v_pkg      uuid;
  v_admins   integer;
  v_res      jsonb;
  v_a        uuid;
  v_b        uuid;
  v_c        uuid;
  v_d        uuid;
  v_e        uuid;
  v_p        uuid;
  v_n        integer;
  v_row      public.digital_orders%ROWTYPE;
  v_title    text;
  v_content  text;
  v_checks   integer := 0;
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
  SELECT count(*) INTO v_admins FROM public.profiles WHERE role = 'admin';
  UPDATE public.user_balances SET balance = 1000 WHERE user_id = v_buyer;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);

  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, product_type,
      is_available, smm_provider_id, smm_service_id, price_per_1000, min_quantity, max_quantity)
  VALUES (v_shop, 'TEST Bildirim Takipçi', 'test-bildirim-' || substr(md5(random()::text), 1, 8),
      10, 0, 'digital', true, v_provider, '999', 10, 100, 10000)
  RETURNING id INTO v_smm;

  -- [1] SMM siparişi açılınca durum/kazanç/satıcı bildirimi yok
  v_res := public.create_digital_order_with_points(v_buyer, v_smm, 'https://instagram.com/n1', 1500,
    'test-notify-a-0001', false);
  v_a := (v_res ->> 'digital_order_id')::uuid;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE entity_id = v_a::text
     AND type IN ('digital_order_status', 'digital_order_commission', 'seller_new_digital_order');
  IF v_n <> 0 THEN RAISE EXCEPTION '[1] yeni SMM siparişinde % bildirim', v_n; END IF;
  v_checks := v_checks + 1;

  -- [2] pending → in_progress: bildirim yok
  UPDATE public.digital_orders SET status = 'in_progress' WHERE id = v_a;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE entity_id = v_a::text AND type = 'digital_order_status';
  IF v_n <> 0 THEN RAISE EXCEPTION '[2] in_progress bildirimi %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [3] tamamlandı (status-check sırası): alıcıya 1, yöneticilere kazanç bildirimi
  PERFORM public.set_digital_order_reconciliation(v_a, 'settled');
  PERFORM public.credit_digital_order_seller(v_a, 1);
  UPDATE public.digital_orders SET status = 'completed', last_checked_at = now() WHERE id = v_a;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE user_id = v_buyer AND type = 'digital_order_status' AND entity_id = v_a::text
     AND title = 'Dijital Siparişiniz Tamamlandı'
     AND content = 'TEST Bildirim Takipçi siparişiniz tamamlandı.'
     AND data ->> 'status' = 'completed' AND data ->> 'digital_order_id' = v_a::text;
  IF v_n <> 1 THEN RAISE EXCEPTION '[3] tamamlandı bildirimi %', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE type = 'digital_order_commission' AND entity_id = v_a::text
     AND title = 'Dijital Sipariş Kazancı'
     AND content LIKE '% mağazasına TEST Bildirim Takipçi satışından ₺%kazanç eklendi (komisyon: ₺%).'
     AND data ->> 'shop_id' = v_shop::text;
  IF v_n <> v_admins THEN RAISE EXCEPTION '[3] kazanç bildirimi % (yönetici %)', v_n, v_admins; END IF;
  v_checks := v_checks + 1;

  -- [4] tekrarlar (ağ tekrarı / status-check aynı durumu yeniden yazar): yeni bildirim yok
  PERFORM public.credit_digital_order_seller(v_a, 1);
  UPDATE public.digital_orders SET status = 'completed', remains = 0, last_checked_at = now()
   WHERE id = v_a;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE entity_id = v_a::text AND type = 'digital_order_status';
  IF v_n <> 1 THEN RAISE EXCEPTION '[4] tekrar sonrası durum bildirimi %', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE entity_id = v_a::text AND type = 'digital_order_commission';
  IF v_n <> v_admins THEN RAISE EXCEPTION '[4] tekrar sonrası kazanç bildirimi %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [5] kısmi: 1500'ün 500'ü teslim edilmedi → ₺15.00 × 500/1500 = ₺5.00 iade
  v_res := public.create_digital_order_with_points(v_buyer, v_smm, 'https://instagram.com/n2', 1500,
    'test-notify-b-0001', false);
  v_b := (v_res ->> 'digital_order_id')::uuid;
  PERFORM public.set_digital_order_reconciliation(v_b, 'settled');
  PERFORM public.refund_digital_order_payment(v_b, 5.00, 'provider-outcome:' || v_b || ':partial:500',
    'Test kısmi', false);
  PERFORM public.credit_digital_order_seller(v_b, 1000 / 1500.0);
  UPDATE public.digital_orders SET status = 'partial', remains = 500 WHERE id = v_b;
  SELECT count(*), max(title), max(content) INTO v_n, v_title, v_content FROM public.notifications
   WHERE user_id = v_buyer AND type = 'digital_order_status' AND entity_id = v_b::text;
  IF v_n <> 1 OR v_title <> 'Dijital Siparişiniz Kısmi Tamamlandı'
     OR v_content <> 'TEST Bildirim Takipçi siparişinizin bir kısmı teslim edildi. Teslim edilmeyen kısmın iadesi: ₺5.00 bakiye.' THEN
    RAISE EXCEPTION '[5] kısmi bildirim % / % / %', v_n, v_title, v_content;
  END IF;
  v_checks := v_checks + 1;

  -- [6] iptal (kesin): tam iade, satıcı kazancı/bildirimi yok
  v_res := public.create_digital_order_with_points(v_buyer, v_smm, 'https://instagram.com/n3', 1000,
    'test-notify-c-0001', false);
  v_c := (v_res ->> 'digital_order_id')::uuid;
  PERFORM public.refund_digital_order_payment(v_c, 10.00, 'provider-outcome:' || v_c || ':canceled:1000',
    'Test iptal', true);
  UPDATE public.digital_orders SET status = 'canceled' WHERE id = v_c;
  SELECT count(*), max(title), max(content) INTO v_n, v_title, v_content FROM public.notifications
   WHERE user_id = v_buyer AND type = 'digital_order_status' AND entity_id = v_c::text;
  IF v_n <> 1 OR v_title <> 'Dijital Siparişiniz İade Edildi'
     OR v_content <> 'TEST Bildirim Takipçi siparişiniz iptal edildi. İade: ₺10.00 bakiye.' THEN
    RAISE EXCEPTION '[6] iptal bildirimi % / % / %', v_n, v_title, v_content;
  END IF;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE entity_id = v_c::text AND type = 'digital_order_commission';
  IF v_n <> 0 THEN RAISE EXCEPTION '[6] iptalde kazanç bildirimi %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [7] failed (yetkili kesin karar): eski sürüm burada iade/bildirim yapmıyordu
  v_res := public.create_digital_order_with_points(v_buyer, v_smm, 'https://instagram.com/n4', 1000,
    'test-notify-d-0001', false);
  v_d := (v_res ->> 'digital_order_id')::uuid;
  PERFORM public.refund_digital_order_payment(v_d, 10.00, 'provider-outcome:' || v_d || ':failed:1000',
    'Test başarısız', true);
  UPDATE public.digital_orders SET status = 'failed' WHERE id = v_d;
  SELECT count(*), max(content) INTO v_n, v_content FROM public.notifications
   WHERE user_id = v_buyer AND type = 'digital_order_status' AND entity_id = v_d::text
     AND title = 'Dijital Siparişiniz İade Edildi';
  IF v_n <> 1 OR v_content <> 'TEST Bildirim Takipçi siparişiniz gerçekleştirilemedi. İade: ₺10.00 bakiye.' THEN
    RAISE EXCEPTION '[7] failed bildirimi % / %', v_n, v_content;
  END IF;
  v_checks := v_checks + 1;

  -- [8] puanlı ödeme: iade puan puana, TL bakiyeye döner ve metinde ayrı
  -- görünür (eski sürüm tamamını TL yapıyordu). ₺10.00'ın %30'u puanla.
  UPDATE public.ad_settings
     SET reward_points_spend_enabled = true, reward_points_eligible_products_enabled = true
   WHERE id = 1;
  UPDATE public.products SET is_points_eligible = true, max_points_coverage_percent = 30
   WHERE id = v_smm;
  PERFORM public.reward_points_apply_entry(v_buyer, 'admin_correction_credit', 'credit', 1000000,
    'admin_case', gen_random_uuid(), 'test-notify-points-0001', '{}'::jsonb);
  v_res := public.create_digital_order_with_points(v_buyer, v_smm, 'https://instagram.com/n5', 1000,
    'test-notify-e-0001', true);
  v_e := (v_res ->> 'digital_order_id')::uuid;
  SELECT * INTO v_row FROM public.digital_orders WHERE id = v_e;
  IF v_row.points_spent <= 0 OR v_row.points_discount_try <> 3.00 OR v_row.cash_balance_paid_try <> 7.00 THEN
    RAISE EXCEPTION '[8] puanlı sipariş bileşimi %', row_to_json(v_row);
  END IF;
  PERFORM public.refund_digital_order_payment(v_e, 10.00, 'provider-outcome:' || v_e || ':refunded:1000',
    'Test iade', true);
  UPDATE public.digital_orders SET status = 'refunded' WHERE id = v_e;
  SELECT max(content) INTO v_content FROM public.notifications
   WHERE type = 'digital_order_status' AND entity_id = v_e::text;
  IF v_content IS DISTINCT FROM
     'TEST Bildirim Takipçi siparişiniz iade edildi. İade: ₺7.00 bakiye + ' || v_row.points_spent || ' puan.' THEN
    RAISE EXCEPTION '[8] bileşim metni %', v_content;
  END IF;
  v_checks := v_checks + 1;

  -- [9] paket: yeni siparişte satıcıya tek bildirim, teslimde alıcıya eski metin
  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, product_type,
      digital_mode, is_available)
  VALUES (v_shop, 'TEST Bildirim Paketi', 'test-bildirim-paket-' || substr(md5(random()::text), 1, 8),
      49.90, 0, 'digital', 'package', true)
  RETURNING id INTO v_pkg;
  v_res := public.create_digital_order_with_points(v_buyer, v_pkg, 'https://instagram.com/n6', 1,
    'test-notify-p-0001', false);
  v_p := (v_res ->> 'digital_order_id')::uuid;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE user_id = v_seller AND type = 'seller_new_digital_order' AND entity_id = v_p::text;
  IF v_n <> 1 THEN RAISE EXCEPTION '[9] satıcı paket bildirimi %', v_n; END IF;
  PERFORM public.set_digital_order_reconciliation(v_p, 'settled');
  PERFORM public.credit_digital_order_seller(v_p, 1);
  UPDATE public.digital_orders SET status = 'completed' WHERE id = v_p;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE user_id = v_buyer AND type = 'digital_order_status' AND entity_id = v_p::text
     AND title = 'Paketiniz teslim edildi'
     AND content = 'TEST Bildirim Paketi siparişiniz satıcı tarafından teslim edildi.';
  IF v_n <> 1 THEN RAISE EXCEPTION '[9] paket teslim bildirimi %', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE entity_id = v_p::text AND type = 'digital_order_status';
  IF v_n <> 1 THEN RAISE EXCEPTION '[9] paket durum bildirimi toplamı %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [10] her sipariş için tam olarak bir alıcı durum bildirimi
  SELECT count(*) INTO v_n FROM (
    SELECT entity_id FROM public.notifications
     WHERE type = 'digital_order_status'
       AND entity_id IN (v_a::text, v_b::text, v_c::text, v_d::text, v_e::text, v_p::text)
     GROUP BY entity_id HAVING count(*) = 1
  ) x;
  IF v_n <> 6 THEN RAISE EXCEPTION '[10] tekil bildirimli sipariş sayısı %', v_n; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol (yönetici %)', v_checks, v_admins;
END;
$test$;
