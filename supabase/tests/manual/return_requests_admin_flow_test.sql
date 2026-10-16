-- Müşteri iadesi (tümü / seçili ürün) + yönetici onaylı akış — canlı doğrulama.
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/return_requests_admin_flow_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası: DO bloğu RAISE EXCEPTION ile biter,
-- testin yazdığı her şey (sipariş kalemleri, bakiye, mağaza hesabı, stok,
-- bildirimler) geri alınır.
DO $test$
DECLARE
  v_order     uuid;
  v_customer  uuid;
  v_shop      uuid;
  v_owner     uuid;
  v_admin     uuid;
  v_other     uuid;
  v_product   uuid;
  v_item_a    uuid := gen_random_uuid();
  v_item_b    uuid := gen_random_uuid();
  v_req       public.return_requests;
  v_req1      uuid;
  v_req2      uuid;
  v_total     numeric;
  v_fee       numeric;
  v_net       numeric;
  v_ratio     numeric;
  v_share     numeric;
  v_goods     numeric;
  v_exp       numeric;
  v_bal0      numeric;
  v_bal1      numeric;
  v_credit0   numeric;
  v_credit1   numeric;
  v_stock0    integer;
  v_stock1    integer;
  v_n         integer;
  v_json      jsonb;
  v_state     text;
  v_log       text := '';
  v_checks    integer := 0;
BEGIN
  -- ── Fikstür ──────────────────────────────────────────────────────────────
  SELECT o.id, o.user_id, o.shop_id, s.owner_id
    INTO v_order, v_customer, v_shop, v_owner
    FROM public.orders o
    JOIN public.shops s ON s.id = o.shop_id
    JOIN public.profiles pc ON pc.id = o.user_id
    JOIN public.profiles ps ON ps.id = s.owner_id
   WHERE o.status = 'delivered'
     AND pc.role::text <> 'admin' AND ps.role::text <> 'admin'
     AND o.user_id <> s.owner_id
     AND EXISTS (SELECT 1 FROM public.products p
                  WHERE p.shop_id = o.shop_id AND NOT p.stock_unlimited
                    AND COALESCE(p.product_type, 'physical') <> 'digital')
   ORDER BY o.created_at DESC LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_other FROM public.profiles
   WHERE role::text <> 'admin' AND id NOT IN (v_customer, v_owner) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_product FROM public.products
   WHERE shop_id = v_shop AND NOT stock_unlimited AND COALESCE(product_type, 'physical') <> 'digital'
   ORDER BY created_at LIMIT 1;
  IF v_order IS NULL OR v_admin IS NULL OR v_other IS NULL OR v_product IS NULL THEN
    RAISE EXCEPTION 'test verisi bulunamadı';
  END IF;

  DELETE FROM public.return_requests WHERE order_id = v_order;

  -- Kalemleri tetikleyicisiz kur: A = 2 adet × 20 (ürünlü), B = 1 adet × 30.
  EXECUTE 'ALTER TABLE public.order_items DISABLE TRIGGER USER';
  DELETE FROM public.order_items WHERE order_id = v_order;
  INSERT INTO public.order_items (id, order_id, product_id, product_name, product_price, price, quantity, subtotal, shop_id)
  VALUES (v_item_a, v_order, v_product, 'Test Ürün A', 20, 20, 2, 40, v_shop),
         (v_item_b, v_order, NULL,      'Test Ürün B', 30, 30, 1, 30, v_shop);
  EXECUTE 'ALTER TABLE public.order_items ENABLE TRIGGER USER';

  -- 70 mal + 5 teslimat − 7 kupon = 68; komisyon 7 (ara toplamın %10'u).
  -- Satıcıdan geri alınan = iade − iade edilen tutarın komisyonu.
  UPDATE public.orders
     SET subtotal = 70, delivery_fee = 5, discount = 7, coupon_discount = 0, total = 68,
         seller_net_amount = 61.20, seller_credit_amount = 61.20, admin_commission = 7,
         commission_status = 'admin_collects', payment_method = 'balance',
         payment_status = 'paid', delivered_at = now()
   WHERE id = v_order;
  SELECT total, delivery_fee, seller_net_amount INTO v_total, v_fee, v_net
    FROM public.orders WHERE id = v_order;
  v_goods := v_total - v_fee;
  v_ratio := LEAST(v_goods / 70, 1);
  v_share := 7 / v_goods;  -- iade tutarının komisyon oranı

  UPDATE public.shops SET admin_credit = 100, commission_debt = 0 WHERE id = v_shop;
  INSERT INTO public.user_balances (user_id, balance) VALUES (v_customer, 0)
  ON CONFLICT (user_id) DO NOTHING;
  SELECT balance INTO v_bal0 FROM public.user_balances WHERE user_id = v_customer;
  SELECT stock_quantity INTO v_stock0 FROM public.products WHERE id = v_product;

  -- ── [1] doğrudan yazma kapalı ───────────────────────────────────────────
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  BEGIN
    INSERT INTO public.return_requests (order_id, user_id, shop_id, reason)
    VALUES (v_order, v_customer, v_shop, 'doğrudan');
    RAISE EXCEPTION '[1] doğrudan INSERT engellenmedi';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- ── [2] başkası iade açamaz ─────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.create_return_request(v_order, 'başkasının siparişi', NULL);
    RAISE EXCEPTION '[2] yabancı kullanıcı iade açabildi';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- ── [3] doğrulamalar: sebep, fazla adet, sipariş dışı kalem, süre ────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.create_return_request(v_order, ' a ', NULL);
    RAISE EXCEPTION '[3a] kısa sebep kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.create_return_request(v_order, 'fazla adet',
      jsonb_build_array(jsonb_build_object('order_item_id', v_item_a, 'quantity', 3)));
    RAISE EXCEPTION '[3b] fazla adet kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.create_return_request(v_order, 'yabancı kalem',
      jsonb_build_array(jsonb_build_object('order_item_id', gen_random_uuid(), 'quantity', 1)));
    RAISE EXCEPTION '[3c] sipariş dışı kalem kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.create_return_request(v_order, 'bozuk adet',
      jsonb_build_array(jsonb_build_object('order_item_id', v_item_a, 'quantity', 'iki')));
    RAISE EXCEPTION '[3d] bozuk adet kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  EXECUTE 'RESET ROLE';
  UPDATE public.orders SET delivered_at = now() - interval '20 days' WHERE id = v_order;
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.create_return_request(v_order, 'süre geçti', NULL);
    RAISE EXCEPTION '[3e] süresi geçmiş sipariş kabul edildi';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_state = MESSAGE_TEXT;
    IF v_state NOT LIKE 'İade süresi doldu%' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  UPDATE public.orders SET delivered_at = now() WHERE id = v_order;
  v_checks := v_checks + 1;

  -- ── [4] kısmi talep (A × 1) + aynı anda ikinci bekleyen talep yok ───────
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_req := public.create_return_request(v_order, 'Ürün A hasarlı geldi',
    jsonb_build_array(jsonb_build_object('order_item_id', v_item_a, 'quantity', 1)));
  v_exp := round(20 * v_ratio, 2);
  IF v_req.status <> 'pending' OR v_req.return_scope <> 'partial' OR v_req.refund_amount <> v_exp THEN
    RAISE EXCEPTION '[4] kısmi talep yanlış: % % % (beklenen %)', v_req.status, v_req.return_scope, v_req.refund_amount, v_exp;
  END IF;
  SELECT count(*) INTO v_n FROM public.return_request_items WHERE request_id = v_req.id;
  IF v_n <> 1 THEN RAISE EXCEPTION '[4] kalem sayısı %', v_n; END IF;
  BEGIN
    PERFORM public.create_return_request(v_order, 'ikinci talep', NULL);
    RAISE EXCEPTION '[4] ikinci bekleyen talep açılabildi';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_state = MESSAGE_TEXT;
    IF v_state NOT LIKE '%bekleyen%' THEN RAISE; END IF;
  END;
  v_log := v_log || ' kısmi=' || v_req.refund_amount;
  v_checks := v_checks + 1;

  -- ── [5] yöneticilere bildirim + müşteri geri çeker ──────────────────────
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE type = 'return_request' AND entity_id = v_req.id::text;
  IF v_n <> (SELECT count(*) FROM public.profiles WHERE role::text = 'admin') THEN
    RAISE EXCEPTION '[5] yönetici bildirimi sayısı %', v_n;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_req := public.cancel_return_request(v_req.id);
  IF v_req.status <> 'cancelled' THEN RAISE EXCEPTION '[5] geri çekilmedi'; END IF;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE type = 'return_request' AND entity_id = v_req.id::text;
  IF v_n <> 0 THEN RAISE EXCEPTION '[5] geri çekilen talebin yönetici bildirimi kaldı'; END IF;
  v_checks := v_checks + 1;

  -- ── [6] satıcı ve müşteri onaylayamaz; yönetici onaylar ─────────────────
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_req := public.create_return_request(v_order, 'Ürün A hasarlı geldi',
    jsonb_build_array(jsonb_build_object('order_item_id', v_item_a, 'quantity', 1)));
  v_req1 := v_req.id;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.approve_return_request(v_req1, NULL);
    RAISE EXCEPTION '[6] satıcı onaylayabildi';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.mark_return_received(v_req1, false);
    RAISE EXCEPTION '[6] onaysız talep teslim alındı yapılabildi';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_req := public.approve_return_request(v_req1, 'Onaylandı');
  EXECUTE 'RESET ROLE';
  SELECT balance INTO v_bal1 FROM public.user_balances WHERE user_id = v_customer;
  SELECT admin_credit INTO v_credit1 FROM public.shops WHERE id = v_shop;
  v_exp := v_req.refund_amount - round(v_req.refund_amount * v_share, 2);
  IF v_req.status <> 'approved' OR v_req.balance_transaction_id IS NULL
     OR v_bal1 - v_bal0 <> v_req.refund_amount
     OR v_req.seller_debit_amount <> v_exp
     OR v_credit1 <> 100 - v_exp THEN
    RAISE EXCEPTION '[6] onay hesabı yanlış: durum % bakiye +% iade % satıcı % (beklenen %) kredi %',
      v_req.status, v_bal1 - v_bal0, v_req.refund_amount, v_req.seller_debit_amount, v_exp, v_credit1;
  END IF;
  IF (SELECT payment_status::text FROM public.orders WHERE id = v_order) = 'refunded' THEN
    RAISE EXCEPTION '[6] kısmi iadede ödeme refunded oldu';
  END IF;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE entity_id = v_req1::text
     AND ((type = 'return_approved' AND user_id = v_customer)
       OR (type = 'return_approved_seller' AND user_id = v_owner));
  IF v_n <> 2 THEN RAISE EXCEPTION '[6] müşteri/satıcı bildirimi %', v_n; END IF;
  v_log := v_log || ' satıcı1=' || v_req.seller_debit_amount;
  v_checks := v_checks + 1;

  -- ── [7] kalan tümü: yönetici reddeder, müşteri yeniden açar ─────────────
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  v_req := public.create_return_request(v_order, 'Kalanları da iade ediyorum', NULL);
  v_exp := v_goods - round(20 * v_ratio, 2);
  IF v_req.refund_amount <> v_exp OR v_req.return_scope <> 'partial' THEN
    RAISE EXCEPTION '[7] kalan tümü yanlış: % % (beklenen %)', v_req.return_scope, v_req.refund_amount, v_exp;
  END IF;
  SELECT sum(quantity) INTO v_n FROM public.return_request_items WHERE request_id = v_req.id;
  IF v_n <> 2 THEN RAISE EXCEPTION '[7] kalan adet %', v_n; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.reject_return_request(v_req.id, 'x');
    RAISE EXCEPTION '[7] gerekçesiz red kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  v_req := public.reject_return_request(v_req.id, 'Ürün kullanılmış');
  IF v_req.status <> 'rejected' THEN RAISE EXCEPTION '[7] reddedilmedi'; END IF;
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM public.notifications
                  WHERE type = 'return_rejected' AND user_id = v_customer AND entity_id = v_req.id::text) THEN
    RAISE EXCEPTION '[7] red bildirimi yok';
  END IF;
  v_checks := v_checks + 1;

  -- ── [8] son talep: tam kalan tutar, ödeme refunded, satıcı payı tamamlanır
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  v_req := public.create_return_request(v_order, 'Kalanları da iade ediyorum', NULL);
  v_req2 := v_req.id;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_req := public.approve_return_request(v_req2, NULL);
  EXECUTE 'RESET ROLE';
  SELECT balance INTO v_bal1 FROM public.user_balances WHERE user_id = v_customer;
  SELECT admin_credit INTO v_credit1 FROM public.shops WHERE id = v_shop;
  IF v_bal1 - v_bal0 <> v_goods THEN
    RAISE EXCEPTION '[8] toplam iade % (beklenen %)', v_bal1 - v_bal0, v_goods;
  END IF;
  IF (SELECT sum(seller_debit_amount) FROM public.return_requests
       WHERE order_id = v_order AND status IN ('approved', 'completed')) <> v_goods - 7 THEN
    RAISE EXCEPTION '[8] satıcıdan düşülen toplam yanlış';
  END IF;
  IF v_credit1 <> 100 - (v_goods - 7) THEN
    RAISE EXCEPTION '[8] mağaza kredisi % (beklenen %)', v_credit1, 100 - (v_goods - 7);
  END IF;
  IF (SELECT payment_status::text FROM public.orders WHERE id = v_order) <> 'refunded' THEN
    RAISE EXCEPTION '[8] tam iadede ödeme refunded olmadı';
  END IF;
  v_log := v_log || ' toplam=' || (v_bal1 - v_bal0) || ' kredi=' || v_credit1;
  v_checks := v_checks + 1;

  -- ── [9] tamamı iade edilmiş siparişe yeni talep yok ─────────────────────
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.create_return_request(v_order, 'tekrar', NULL);
    RAISE EXCEPTION '[9] iade edilmiş siparişe yeni talep açıldı';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_state = MESSAGE_TEXT;
    IF v_state NOT LIKE '%zaten iade%' THEN RAISE; END IF;
  END;
  v_checks := v_checks + 1;

  -- ── [10] teslim alma: yabancı yapamaz, satıcı stoğa ekleyerek kapatır ───
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.mark_return_received(v_req2, true);
    RAISE EXCEPTION '[10] yabancı teslim alabildi';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_req := public.mark_return_received(v_req2, true);
  IF v_req.status <> 'completed' OR NOT v_req.restocked THEN RAISE EXCEPTION '[10] tamamlanmadı'; END IF;
  v_req := public.mark_return_received(v_req1, false) ;
  EXECUTE 'RESET ROLE';
  SELECT stock_quantity INTO v_stock1 FROM public.products WHERE id = v_product;
  IF v_stock1 <> v_stock0 + 1 THEN
    RAISE EXCEPTION '[10] stok % → % (yalnız ikinci talepteki 1 adet eklenmeliydi)', v_stock0, v_stock1;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications
                  WHERE type = 'return_completed' AND user_id = v_customer AND entity_id = v_req2::text) THEN
    RAISE EXCEPTION '[10] tamamlandı bildirimi yok';
  END IF;
  v_checks := v_checks + 1;

  -- ── [11] onaylı iadesi olan sipariş admin iptaline kapalı ───────────────
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_cancel_with_refund(v_order, 'çifte iade denemesi');
    RAISE EXCEPTION '[11] onaylı iadeli sipariş iptal edildi';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_state = MESSAGE_TEXT;
    IF v_state NOT LIKE '%onaylanmış iade%' THEN RAISE; END IF;
  END;
  v_checks := v_checks + 1;

  -- ── [12] listeler: müşteri / satıcı / yönetici ──────────────────────────
  v_json := public.get_return_requests('admin', NULL, v_order);
  IF jsonb_array_length(v_json) <> 4 THEN RAISE EXCEPTION '[12] admin listesi %', jsonb_array_length(v_json); END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_json := public.get_return_requests('seller', NULL, v_order);
  IF jsonb_array_length(v_json) <> 4 OR v_json -> 0 ->> 'customer_name' IS NULL
     OR jsonb_array_length(v_json -> 0 -> 'items') < 1 THEN
    RAISE EXCEPTION '[12] satıcı listesi yanlış: %', left(v_json::text, 300);
  END IF;
  BEGIN
    PERFORM public.get_return_requests('admin', NULL, NULL);
    RAISE EXCEPTION '[12] satıcı admin listesini okudu';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  v_json := public.get_return_requests('customer', 'completed', NULL);
  IF (SELECT count(*) FROM jsonb_array_elements(v_json) e WHERE e ->> 'order_id' = v_order::text) <> 2 THEN
    RAISE EXCEPTION '[12] müşteri tamamlanan listesi yanlış';
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  v_json := public.get_return_requests('customer', NULL, v_order);
  IF jsonb_array_length(v_json) <> 0 THEN RAISE EXCEPTION '[12] yabancı müşteri talepleri gördü'; END IF;
  SELECT count(*) INTO v_n FROM public.return_request_items i
    JOIN public.return_requests r ON r.id = i.request_id WHERE r.order_id = v_order;
  IF v_n <> 0 THEN RAISE EXCEPTION '[12] yabancı iade kalemlerini gördü (RLS)'; END IF;
  EXECUTE 'RESET ROLE';
  v_checks := v_checks + 1;

  -- ── [13] kuryeli satıcı + kapıda nakit: satıcı nakit iade eder, komisyon
  --        borcu iade edilen tutarın komisyonu kadar düşer, bakiyeye iade yok
  DELETE FROM public.return_requests WHERE order_id = v_order;
  UPDATE public.orders
     SET delivery_fee = 0, discount = 0, total = 70, payment_method = 'cash',
         payment_status = 'paid', commission_status = 'cash_collected',
         admin_commission = 7, seller_net_amount = 63, seller_debt_amount = 7,
         delivered_at = now()
   WHERE id = v_order;
  UPDATE public.shops
     SET commission_debt = 7, admin_credit = 0, total_collected_cash = 70, cash_payment_revenue = 63
   WHERE id = v_shop;
  SELECT balance INTO v_bal0 FROM public.user_balances WHERE user_id = v_customer;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  v_req := public.create_return_request(v_order, 'A bozuk geldi',
    jsonb_build_array(jsonb_build_object('order_item_id', v_item_a, 'quantity', 1)));
  IF v_req.refund_method <> 'seller_cash' OR v_req.refund_amount <> 20 THEN
    RAISE EXCEPTION '[13] nakit talep yanlış: % %', v_req.refund_method, v_req.refund_amount;
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_req := public.approve_return_request(v_req.id, NULL);
  EXECUTE 'RESET ROLE';
  IF v_req.commission_refund_amount <> 2 OR v_req.seller_debit_amount <> 0
     OR v_req.balance_transaction_id IS NOT NULL
     OR (SELECT commission_debt FROM public.shops WHERE id = v_shop) <> 5 THEN
    RAISE EXCEPTION '[13] kısmi nakit iade: komisyon % satıcı % borç %', v_req.commission_refund_amount,
      v_req.seller_debit_amount, (SELECT commission_debt FROM public.shops WHERE id = v_shop);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications
                  WHERE type = 'return_approved' AND entity_id = v_req.id::text
                    AND content LIKE '%satıcıdan nakit%') THEN
    RAISE EXCEPTION '[13] müşteri bildirimi nakit iadeyi söylemiyor';
  END IF;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  v_req := public.create_return_request(v_order, 'Kalanlar da', NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_req := public.approve_return_request(v_req.id, NULL);
  EXECUTE 'RESET ROLE';
  SELECT balance INTO v_bal1 FROM public.user_balances WHERE user_id = v_customer;
  IF v_req.refund_amount <> 50 OR v_req.commission_refund_amount <> 5
     OR (SELECT commission_debt FROM public.shops WHERE id = v_shop) <> 0
     OR (SELECT total_collected_cash FROM public.shops WHERE id = v_shop) <> 0
     OR (SELECT cash_payment_revenue FROM public.shops WHERE id = v_shop) <> 0
     OR v_bal1 <> v_bal0 THEN
    RAISE EXCEPTION '[13] tam nakit iade: iade % komisyon % borç % nakit % gelir % bakiye farkı %',
      v_req.refund_amount, v_req.commission_refund_amount,
      (SELECT commission_debt FROM public.shops WHERE id = v_shop),
      (SELECT total_collected_cash FROM public.shops WHERE id = v_shop),
      (SELECT cash_payment_revenue FROM public.shops WHERE id = v_shop), v_bal1 - v_bal0;
  END IF;
  v_log := v_log || ' nakit_borç=7→5→0';
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol;%', v_checks, v_log;
END;
$test$;
