-- Sipariş para akışı simülasyonu (kuryeli/kuryesiz × ödeme şekli, ücretsiz teslimat,
-- Gel Al, ödeme isteği + onayı, ücretsiz teslimatlı siparişin iadesi).
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/order_money_flow_simulation.sql
-- Sonuç tablo olarak 'SIM' istisnasında yazılır; DO bloğu istisnayla bittiği için her şey geri alınır.
DO $sim$
DECLARE
  v_shop uuid; v_owner uuid; v_user uuid; v_admin uuid; v_order uuid;
  v_out text := '';
  v_case record;
  o record; s1 record;
  v_req public.return_requests;
  v_item uuid;
BEGIN
  SELECT s.id, s.owner_id INTO v_shop, v_owner FROM public.shops s
    JOIN public.profiles p ON p.id = s.owner_id
   WHERE p.role::text <> 'admin' ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_user FROM public.profiles WHERE role::text = 'customer' AND id <> v_owner ORDER BY created_at LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' LIMIT 1;

  -- Ürünler 100 ₺, %10; dükkan teslimat ücreti 50 ₺.
  FOR v_case IN
    SELECT * FROM (VALUES
      ('A kuryesiz, müşteri teslimat öder', false, 50::numeric, 50::numeric, false, 'balance', 0::numeric),
      ('B kuryesiz, satıcı ücretsiz verdi', false, 50, 0, false, 'balance', 0),
      ('C kuryesiz, admin teslimatı 0 yaptı', false, 0, 0, false, 'balance', 0),
      ('D kuryesiz, Gel Al', false, 50, 0, true, 'balance', 0),
      ('E kuryesiz, ücretsiz + kapıda nakit', false, 50, 0, false, 'cash', 0),
      ('F kuryeli, online, teslimat 50', true, 50, 50, false, 'online', 0),
      ('G kuryeli, kapıda nakit, teslimat 50', true, 50, 50, false, 'cash', 0),
      ('H kuryeli, ücretsiz teslimat', true, 50, 0, false, 'balance', 0),
      ('I kuryesiz, 10 kupon, teslimat öder', false, 50, 50, false, 'balance', 10),
      ('J kuryesiz, 10 kupon, ücretsiz tesl.', false, 50, 0, false, 'balance', 10),
      ('K kuryeli, 10 kupon, kapıda nakit', true, 50, 50, false, 'cash', 10),
      ('L kuryeli, 10 kupon, online', true, 50, 50, false, 'online', 10)
    ) AS t(label, own, shop_fee, order_fee, pickup, pm, disc)
  LOOP
    UPDATE public.shops
       SET has_own_courier = v_case.own, commission_rate = 10, delivery_fee = v_case.shop_fee,
           admin_credit = 0, commission_debt = 0, total_collected_cash = 0,
           cash_payment_revenue = 0, online_payment_revenue = 0
     WHERE id = v_shop;

    INSERT INTO public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
                               subtotal, delivery_fee, discount, coupon_discount, total, status, is_pickup)
    VALUES ('SIM-' || left(v_case.label, 1), v_user, v_shop, 'sim', v_case.pm::public.payment_method,
            100, v_case.order_fee, v_case.disc, v_case.disc, 100 + v_case.order_fee - v_case.disc,
            'pending', v_case.pickup)
    RETURNING id INTO v_order;
    UPDATE public.orders SET status = 'confirmed' WHERE id = v_order;
    UPDATE public.orders SET status = 'delivered', delivered_at = now() WHERE id = v_order;

    SELECT * INTO o FROM public.orders WHERE id = v_order;
    SELECT admin_credit, commission_debt INTO s1 FROM public.shops WHERE id = v_shop;
    v_out := v_out || E'\n' || rpad(v_case.label, 40) || ' müşteri=' || o.total || ' kupon=' || v_case.disc ||
      ' kom=' || round(o.admin_commission, 2) || ' adminTeslimat=' || o.admin_delivery_fee ||
      ' kesinti=' || o.seller_delivery_charge || ' satıcıNet=' || o.seller_net_amount ||
      ' | alacak=' || s1.admin_credit || ' borç=' || s1.commission_debt;
  END LOOP;

  -- Ödeme isteği: kuryesiz mağaza, alacak 90, borç 10 → en fazla 80
  UPDATE public.shops SET has_own_courier = false, admin_credit = 90, commission_debt = 10 WHERE id = v_shop;
  DELETE FROM public.payout_requests WHERE shop_id = v_shop AND status = 'pending';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  BEGIN
    INSERT INTO public.payout_requests (seller_id, shop_id, total_amount) VALUES (v_owner, v_shop, 85);
    v_out := v_out || E'\nHATA: kuryesiz mağaza borcu aşan 85 ₺ isteyebildi';
  EXCEPTION WHEN raise_exception THEN
    v_out := v_out || E'\nÖdeme isteği (alacak 90, borç 10): 85 ₺ reddedildi';
  END;
  INSERT INTO public.payout_requests (seller_id, shop_id, total_amount) VALUES (v_owner, v_shop, 80);
  v_out := v_out || ', 80 ₺ kabul edildi';
  EXECUTE 'RESET ROLE';
  UPDATE public.payout_requests SET status = 'approved' WHERE shop_id = v_shop AND status = 'pending';
  SELECT admin_credit, commission_debt INTO s1 FROM public.shops WHERE id = v_shop;
  v_out := v_out || E'
Tam ödeme onayı (80): alacak=' || s1.admin_credit || ' borç=' || s1.commission_debt;
  UPDATE public.shops SET admin_credit = 90, commission_debt = 10 WHERE id = v_shop;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  INSERT INTO public.payout_requests (seller_id, shop_id, total_amount) VALUES (v_owner, v_shop, 50);
  EXECUTE 'RESET ROLE';
  UPDATE public.payout_requests SET status = 'approved' WHERE shop_id = v_shop AND status = 'pending';
  SELECT admin_credit, commission_debt INTO s1 FROM public.shops WHERE id = v_shop;
  v_out := v_out || E'
Kısmi ödeme onayı (alacak 90, borç 10, ödenen 50): alacak=' || s1.admin_credit || ' borç=' || s1.commission_debt;
  v_out := v_out || E'
Admin bildirimleri: ' || (SELECT count(*) FROM public.notifications WHERE type = 'payout_request' AND entity_type = 'payout_request' AND created_at > now() - interval '1 minute');

  -- İade: B senaryosu (ücretsiz teslimat, satıcı 40 aldı) tamamı iade
  UPDATE public.shops SET has_own_courier = false, delivery_fee = 50, admin_credit = 0, commission_debt = 0 WHERE id = v_shop;
  INSERT INTO public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
                             subtotal, delivery_fee, discount, total, status)
  VALUES ('SIM-R', v_user, v_shop, 'sim', 'balance', 100, 0, 0, 100, 'pending')
  RETURNING id INTO v_order;
  EXECUTE 'ALTER TABLE public.order_items DISABLE TRIGGER USER';
  INSERT INTO public.order_items (order_id, product_name, product_price, price, quantity, subtotal, shop_id)
  VALUES (v_order, 'X', 100, 100, 1, 100, v_shop);
  EXECUTE 'ALTER TABLE public.order_items ENABLE TRIGGER USER';
  UPDATE public.orders SET status = 'confirmed' WHERE id = v_order;
  UPDATE public.orders SET status = 'delivered', delivered_at = now(), payment_status = 'paid' WHERE id = v_order;
  SELECT admin_credit, commission_debt INTO s1 FROM public.shops WHERE id = v_shop;
  v_out := v_out || E'\nİade öncesi (ücretsiz teslimat): alacak=' || s1.admin_credit || ' borç=' || s1.commission_debt;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_req := public.create_return_request(v_order, 'tamamı iade', NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_req := public.approve_return_request(v_req.id, NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_req := public.mark_return_received(v_req.id, false);
  EXECUTE 'RESET ROLE';
  SELECT admin_credit, commission_debt INTO s1 FROM public.shops WHERE id = v_shop;
  v_out := v_out || E'\nİade sonrası: müşteriye=' || v_req.refund_amount || ' satıcıdan=' || v_req.seller_debit_amount ||
    ' alacak=' || s1.admin_credit || ' borç=' || s1.commission_debt;

  -- Kuponlu iade: kuryesiz, 2 × 50 ₺ ürün, 10 ₺ kupon, teslimat 50 ödendi.
  -- Önce bir ürün, sonra kalanı.
  UPDATE public.shops SET has_own_courier = false, delivery_fee = 50, admin_credit = 0, commission_debt = 0 WHERE id = v_shop;
  INSERT INTO public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
                             subtotal, delivery_fee, discount, coupon_discount, total, status)
  VALUES ('SIM-RK', v_user, v_shop, 'sim', 'balance', 100, 50, 10, 10, 140, 'pending')
  RETURNING id INTO v_order;
  EXECUTE 'ALTER TABLE public.order_items DISABLE TRIGGER USER';
  INSERT INTO public.order_items (order_id, product_name, product_price, price, quantity, subtotal, shop_id)
  VALUES (v_order, 'Y', 50, 50, 1, 50, v_shop) RETURNING id INTO v_item;
  INSERT INTO public.order_items (order_id, product_name, product_price, price, quantity, subtotal, shop_id)
  VALUES (v_order, 'Z', 50, 50, 1, 50, v_shop);
  EXECUTE 'ALTER TABLE public.order_items ENABLE TRIGGER USER';
  UPDATE public.orders SET status = 'confirmed' WHERE id = v_order;
  UPDATE public.orders SET status = 'delivered', delivered_at = now(), payment_status = 'paid' WHERE id = v_order;
  SELECT admin_credit, commission_debt INTO s1 FROM public.shops WHERE id = v_shop;
  v_out := v_out || E'\nKuponlu iade (kuryesiz, 2×50 ₺, kupon 10, teslimat 50 ödendi): satıcı alacağı=' || s1.admin_credit;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_req := public.create_return_request(v_order, 'Y bozuk',
    jsonb_build_array(jsonb_build_object('order_item_id', v_item, 'quantity', 1)));
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_req := public.approve_return_request(v_req.id, NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_req := public.mark_return_received(v_req.id, false);
  EXECUTE 'RESET ROLE';
  SELECT admin_credit, commission_debt INTO s1 FROM public.shops WHERE id = v_shop;
  v_out := v_out || E'\n  1 ürün iade: müşteriye=' || v_req.refund_amount || ' satıcıdan=' || v_req.seller_debit_amount ||
    ' komisyon iadesi=' || v_req.commission_refund_amount || ' → alacak=' || s1.admin_credit;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_req := public.create_return_request(v_order, 'kalan', NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_req := public.approve_return_request(v_req.id, NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_req := public.mark_return_received(v_req.id, false);
  EXECUTE 'RESET ROLE';
  SELECT admin_credit, commission_debt INTO s1 FROM public.shops WHERE id = v_shop;
  v_out := v_out || E'\n  kalan iade: müşteriye=' || v_req.refund_amount || ' satıcıdan=' || v_req.seller_debit_amount ||
    ' komisyon iadesi=' || v_req.commission_refund_amount || ' → alacak=' || s1.admin_credit || ' borç=' || s1.commission_debt;

  -- Kuryeli + online: 100 ₺, kupon 10, teslimat 50; tamamı iade
  UPDATE public.shops SET has_own_courier = true, delivery_fee = 50, admin_credit = 0, commission_debt = 0 WHERE id = v_shop;
  INSERT INTO public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
                             subtotal, delivery_fee, discount, coupon_discount, total, status)
  VALUES ('SIM-RL', v_user, v_shop, 'sim', 'online', 100, 50, 10, 10, 140, 'pending')
  RETURNING id INTO v_order;
  EXECUTE 'ALTER TABLE public.order_items DISABLE TRIGGER USER';
  INSERT INTO public.order_items (order_id, product_name, product_price, price, quantity, subtotal, shop_id)
  VALUES (v_order, 'W', 100, 100, 1, 100, v_shop);
  EXECUTE 'ALTER TABLE public.order_items ENABLE TRIGGER USER';
  UPDATE public.orders SET status = 'confirmed' WHERE id = v_order;
  UPDATE public.orders SET status = 'delivered', delivered_at = now(), payment_status = 'paid' WHERE id = v_order;
  SELECT admin_credit INTO s1 FROM public.shops WHERE id = v_shop;
  v_out := v_out || E'\nKuryeli online (100 ₺, kupon 10, teslimat 50): satıcı alacağı=' || s1.admin_credit;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_req := public.create_return_request(v_order, 'tamamı', NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_req := public.approve_return_request(v_req.id, NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_req := public.mark_return_received(v_req.id, false);
  EXECUTE 'RESET ROLE';
  SELECT admin_credit, commission_debt INTO s1 FROM public.shops WHERE id = v_shop;
  v_out := v_out || E'\n  tamamı iade: müşteriye=' || v_req.refund_amount || ' satıcıdan=' || v_req.seller_debit_amount ||
    ' komisyon iadesi=' || v_req.commission_refund_amount || ' → alacak=' || s1.admin_credit || ' borç=' || s1.commission_debt;

  RAISE EXCEPTION 'SIM%', v_out;
END;
$sim$;
