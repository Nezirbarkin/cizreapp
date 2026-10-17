-- ============================================================================
-- 20261017000020_cart_checkout_session_parity — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Ana sepetin oturum akışı: kapıda nakit/kart, bakiye (çok mağaza + Gel Al),
-- kupon, flaş (sepet talebi + rezervasyon), online (iyzico geri çağrısı),
-- idempotency, sahiplik, süre, iptal ve eski akışın kupon toplamı.
--
-- Kendi kendini geri alır (sonda ROLLBACK). Göç öncesi denemek için göç
-- gövdesini (BEGIN/COMMIT/NOTIFY hariç) @@MIGRATION@@ işaretli satırın yerine
-- koyun; uygulandıktan sonra olduğu gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/cart_checkout_session_parity_test.sql
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

CREATE TEMP TABLE _parity_results (n serial, line text) ON COMMIT DROP;

-- Kullanıcı adına RPC çağıran yardımcılar (hata → {"error": ...}).
CREATE FUNCTION pg_temp.prep(p_user uuid, p_items jsonb, p_addr uuid, p_pm text, p_key text,
                             p_coupons uuid[] DEFAULT NULL, p_pickups uuid[] DEFAULT NULL,
                             p_notes text DEFAULT NULL, p_invoice jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  EXECUTE 'set local role authenticated';
  SELECT to_jsonb(x) INTO v FROM public.prepare_checkout_session(
    p_items => p_items, p_address_id => p_addr, p_payment_method => p_pm,
    p_idempotency_key => p_key, p_notes => p_notes, p_invoice_data => p_invoice,
    p_coupon_ids => p_coupons, p_pickup_shop_ids => p_pickups) x;
  EXECUTE 'reset role';
  RETURN v;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM, 'state', SQLSTATE);
END $f$;

CREATE FUNCTION pg_temp.commit(p_user uuid, p_session uuid, p_kind text)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  EXECUTE 'set local role authenticated';
  IF p_kind = 'balance' THEN
    SELECT to_jsonb(x) INTO v FROM public.commit_balance_order(p_session) x;
  ELSE
    SELECT to_jsonb(x) INTO v FROM public.commit_cod_order(p_session) x;
  END IF;
  EXECUTE 'reset role';
  RETURN v;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM, 'state', SQLSTATE);
END $f$;

CREATE FUNCTION pg_temp.as_user(p_user uuid, p_sql text)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  EXECUTE 'set local role authenticated';
  EXECUTE p_sql INTO v;
  EXECUTE 'reset role';
  RETURN v;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM, 'state', SQLSTATE);
END $f$;

DO $test$
declare
  v_u uuid; v_u2 uuid;
  v_shop_a uuid; v_shop_b uuid; v_owner_a uuid; v_owner_b uuid;
  v_pa uuid; v_pb uuid; v_pa_name text;
  v_addr uuid; v_addr2 uuid;
  v_sale uuid; v_coupon uuid;
  v_s jsonb; v_c jsonb; v_x jsonb;
  v_sid uuid; v_oid uuid; v_oid2 uuid; v_txn uuid;
  v_o record; v_cnt int; v_num numeric; v_bal0 numeric; v_bal numeric; v_sold int; v_mine int;
  v_txt text;
  r text := '';
begin
  -- ------------------------------------------------------------ fixture
  select s.id, s.owner_id into v_shop_a, v_owner_a from public.shops s
   where s.is_active and s.owner_id is not null
     and exists (select 1 from public.products p where p.shop_id = s.id
                  and p.price_per_1000 is null and coalesce(p.product_type, 'normal') <> 'digital')
   order by s.created_at limit 1;
  select s.id, s.owner_id into v_shop_b, v_owner_b from public.shops s
   where s.is_active and s.owner_id is not null and s.id <> v_shop_a
     and exists (select 1 from public.products p where p.shop_id = s.id
                  and p.price_per_1000 is null and coalesce(p.product_type, 'normal') <> 'digital')
   order by s.created_at limit 1;
  select p.id, p.name into v_pa, v_pa_name from public.products p
   where p.shop_id = v_shop_a and p.price_per_1000 is null and coalesce(p.product_type, 'normal') <> 'digital'
   order by p.created_at limit 1;
  select p.id into v_pb from public.products p
   where p.shop_id = v_shop_b and p.price_per_1000 is null and coalesce(p.product_type, 'normal') <> 'digital'
   order by p.created_at limit 1;
  select p.id into v_u from public.profiles p join auth.users au on au.id = p.id
   where p.role = 'customer' and coalesce(p.is_admin, false) = false
     and p.id not in (v_owner_a, v_owner_b)
     and not exists (select 1 from public.shops s where s.owner_id = p.id)
   order by p.created_at limit 1;
  select p.id into v_u2 from public.profiles p join auth.users au on au.id = p.id
   where p.role = 'customer' and coalesce(p.is_admin, false) = false
     and p.id not in (v_owner_a, v_owner_b, v_u)
     and not exists (select 1 from public.shops s where s.owner_id = p.id)
   order by p.created_at limit 1;

  r := format('fixtures shopA=%s shopB=%s pa=%s pb=%s u=%s u2=%s',
              v_shop_a is not null, v_shop_b is not null, v_pa is not null,
              v_pb is not null, v_u is not null, v_u2 is not null);

  -- Deterministik fiyat/teslimat (hepsi geri alınır)
  update public.shops set delivery_fee = 15, free_delivery_min_amount = 0, min_order_amount = 0,
         commission_rate = 10, pickup_enabled = true, is_active = true
   where id in (v_shop_a, v_shop_b);
  update public.products set price = 100, discount_price = null, stock_quantity = 50,
         stock_unlimited = false, shipping_fee = null, free_shipping = false,
         min_order_quantity = null, max_order_quantity = null, is_available = true,
         campaign_type = null
   where id in (v_pa, v_pb);
  update public.notification_preferences set order_updates_enabled = true
   where user_id in (v_owner_a, v_owner_b);
  update public.user_balances set balance = 1000, locked_balance = 0 where user_id = v_u;
  if not found then
    insert into public.user_balances (user_id, balance) values (v_u, 1000);
  end if;
  update public.user_balances set balance = 1000, locked_balance = 0 where user_id = v_u2;
  if not found then
    insert into public.user_balances (user_id, balance) values (v_u2, 1000);
  end if;
  delete from private.flash_sale_claims where user_id in (v_u, v_u2);

  insert into public.addresses (user_id, title, full_name, phone, address_line1, address_line2, district, city, postal_code)
  values (v_u, 'Ev', 'Test Musteri', '05550000000', 'Cudi Mah. 1. Sok', 'No 5', 'Merkez', 'Cizre', '73200')
  returning id into v_addr;
  insert into public.addresses (user_id, title, full_name, phone, address_line1, city)
  values (v_u2, 'Is', 'Ikinci Musteri', '05551111111', 'Nuh Cad.', 'Cizre')
  returning id into v_addr2;

  -- ------------------------------------------- 1) kapıda nakit, tek mağaza
  v_s := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 2)),
                      v_addr, 'cash', 'parity-cash-0001', p_notes => 'Kapi kodu 12',
                      p_invoice => jsonb_build_object('invoice_type', 'individual', 'invoice_full_name', 'Test Musteri'));
  v_sid := (v_s->>'session_id')::uuid;
  r := r || chr(10) || case when v_s->>'error' is null
        and (v_s->>'server_subtotal')::numeric = 200 and (v_s->>'server_delivery_fee')::numeric = 15
        and (v_s->>'server_total')::numeric = 215
        and jsonb_array_length(v_s->'sub_orders') = 1
    then 'PASS nakit: sunucu fiyati 200 + 15 teslimat = 215'
    else 'FAIL nakit prepare ' || v_s::text end;

  v_x := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 2)),
                      v_addr, 'cash', 'parity-cash-0001');
  r := r || chr(10) || case when (v_x->>'session_id')::uuid = v_sid
    then 'PASS ayni idempotency anahtari ayni oturumu dondu'
    else 'FAIL idempotency ' || v_x::text end;

  v_c := pg_temp.commit(v_u, v_sid, 'cod');
  v_oid := (v_c->>'order_id')::uuid;
  select o.* into v_o from public.orders o where o.id = v_oid;
  r := r || chr(10) || case when v_c->>'error' is null
        and v_o.payment_method::text = 'cash' and v_o.payment_status::text = 'pending'
        and v_o.status::text = 'pending' and v_o.total = 215 and v_o.subtotal = 200
        and v_o.delivery_fee = 15 and v_o.is_pickup = false and v_o.checkout_session_id = v_sid
        and v_o.delivery_address_text = 'Cudi Mah. 1. Sok, No 5, Merkez, Cizre, 73200'
        and v_o.customer_phone = '05550000000' and v_o.notes = 'Kapi kodu 12'
        and v_o.invoice_full_name = 'Test Musteri' and v_o.order_group_id is null
    then 'PASS nakit: siparis alanlari eski akisla ayni'
    else 'FAIL nakit commit ' || v_c::text || ' / ' || coalesce(to_jsonb(v_o)::text, 'siparis yok') end;

  select count(*), sum(oi.subtotal) into v_cnt, v_num
    from public.order_items oi where oi.order_id = v_oid and oi.price = 100 and oi.quantity = 2;
  r := r || chr(10) || case when v_cnt = 1 and v_num = 200
    then 'PASS nakit: kalem fiyati sunucudan (100 x 2)'
    else format('FAIL nakit kalem cnt=%s sum=%s', v_cnt, v_num) end;

  select count(*) into v_cnt from public.notifications n
   where n.user_id = v_owner_a and n.type = 'new_order' and n.entity_id = v_oid::text;
  r := r || chr(10) || case when v_cnt = 1
    then 'PASS saticiya Yeni Siparis bildirimi gitti'
    else format('FAIL satici bildirimi sayisi=%s', v_cnt) end;

  v_x := pg_temp.commit(v_u, v_sid, 'cod');
  r := r || chr(10) || case when (v_x->>'order_id')::uuid = v_oid
        and (select count(*) from public.orders o where o.checkout_session_id = v_sid) = 1
    then 'PASS ikinci commit ayni siparisi dondu (cift siparis yok)'
    else 'FAIL tekrar commit ' || v_x::text end;

  -- ------------------------------------------- 2) kapıda kart → 'cardOnDelivery'
  v_s := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'card_on_delivery', 'parity-card-0001');
  v_c := pg_temp.commit(v_u, (v_s->>'session_id')::uuid, 'cod');
  select o.payment_method::text into v_txt from public.orders o where o.id = (v_c->>'order_id')::uuid;
  r := r || chr(10) || case when v_txt = 'cardOnDelivery'
    then 'PASS kapida kart uygulamanin enum adiyla yazildi'
    else format('FAIL kapida kart pm=%s %s', v_txt, v_c) end;

  -- ------------------------------------------- 3) sahiplik + süre
  v_s := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'cash', 'parity-owner-0001');
  v_sid := (v_s->>'session_id')::uuid;
  v_x := pg_temp.commit(v_u2, v_sid, 'cod');
  r := r || chr(10) || case when v_x->>'state' = '42501'
    then 'PASS baskasinin oturumu commit edilemedi'
    else 'FAIL yabanci commit ' || v_x::text end;

  update private.server_checkout_sessions set expires_at = now() - interval '1 minute' where id = v_sid;
  v_x := pg_temp.commit(v_u, v_sid, 'cod');
  r := r || chr(10) || case when v_x->>'error' like 'APP: session_expired%'
    then 'PASS suresi dolan oturum commit edilemedi'
    else 'FAIL sure dolumu ' || v_x::text end;

  v_x := pg_temp.prep(v_u2, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'cash', 'parity-addr-0001');
  r := r || chr(10) || case when v_x->>'state' = '42501'
    then 'PASS baskasinin adresiyle oturum acilamadi'
    else 'FAIL yabanci adres ' || v_x::text end;

  -- ------------------------------------------- 4) kupon (sabit 10) + kupon toplamı
  insert into public.shop_coupons (shop_id, code, title, discount_type, discount_value,
                                   minimum_order_amount, usage_per_user, is_active)
  values (v_shop_a, 'PARITY10', 'Test', 'fixed_amount', 10, 0, 1, true)
  returning id into v_coupon;

  v_s := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'cash', 'parity-coupon-0001', p_coupons => array[v_coupon]);
  v_c := pg_temp.commit(v_u, (v_s->>'session_id')::uuid, 'cod');
  select o.* into v_o from public.orders o where o.id = (v_c->>'order_id')::uuid;
  r := r || chr(10) || case when (v_s->>'server_total')::numeric = 105
        and v_o.total = 105 and v_o.coupon_id = v_coupon and v_o.coupon_discount = 10 and v_o.discount = 10
    then 'PASS kupon: 100 - 10 + 15 = 105 (indirim bir kez)'
    else 'FAIL kupon ' || v_s::text || ' / ' || coalesce(to_jsonb(v_o)::text, v_c::text) end;

  select count(*) into v_cnt from public.coupon_usages u
   where u.coupon_id = v_coupon and u.order_id = v_o.id and u.discount_amount = 10;
  r := r || chr(10) || case when v_cnt = 1
        and (select c.usage_count from public.shop_coupons c where c.id = v_coupon) = 1
    then 'PASS kupon kullanimi kaydedildi'
    else format('FAIL kupon kullanimi cnt=%s', v_cnt) end;

  v_x := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'cash', 'parity-coupon-0002', p_coupons => array[v_coupon]);
  r := r || chr(10) || case when v_x->>'error' like 'APP: coupon_used%'
    then 'PASS kisi basi kupon siniri uygulandi'
    else 'FAIL kupon tekrar ' || v_x::text end;

  v_x := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pb, 'quantity', 1)),
                      v_addr, 'cash', 'parity-coupon-0003', p_coupons => array[v_coupon]);
  r := r || chr(10) || case when v_x->>'error' like 'APP: coupon_invalid%'
    then 'PASS baska magazanin kuponu reddedildi'
    else 'FAIL magaza disi kupon ' || v_x::text end;

  -- Eski akış: discount = coupon_discount = 10 → toplam yalnız bir kez düşer
  insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
         payment_status, subtotal, delivery_fee, discount, coupon_discount, total, status)
  values ('PARITYLEGACY1', v_u, v_shop_a, 'eski', 'cash', 'pending', 100, 15, 10, 10, 105, 'pending')
  returning id into v_oid2;
  insert into public.order_items (order_id, product_id, product_name, quantity, price, shop_id)
  values (v_oid2, v_pa, 'eski kalem', 1, 100, v_shop_a);
  select o.total into v_num from public.orders o where o.id = v_oid2;
  r := r || chr(10) || case when v_num = 105
    then 'PASS eski akis kuponlu siparis toplami 105 kaldi (cift indirim yok)'
    else format('FAIL eski akis toplam=%s (beklenen 105)', v_num) end;

  -- ------------------------------------------- 5) min sepet + stok + Gel Al kuralları
  update public.shops set min_order_amount = 500 where id = v_shop_a;
  v_x := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'cash', 'parity-min-0001');
  r := r || chr(10) || case when v_x->>'error' like 'APP: min_order_amount%Eksik tutar: ₺400.00%'
    then 'PASS minimum sepet tutari sunucuda uygulandi'
    else 'FAIL min sepet ' || v_x::text end;
  update public.shops set min_order_amount = 0 where id = v_shop_a;

  v_x := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 60)),
                      v_addr, 'cash', 'parity-stock-0001');
  r := r || chr(10) || case when v_x->>'error' like 'APP: insufficient_stock%'
    then 'PASS stok ustu adet reddedildi'
    else 'FAIL stok ' || v_x::text end;

  v_x := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'cash', 'parity-pickup-0001', p_pickups => array[v_shop_a]);
  r := r || chr(10) || case when v_x->>'error' like 'APP: pickup_requires_balance%'
    then 'PASS Gel Al kapida odemeyle reddedildi'
    else 'FAIL Gel Al nakit ' || v_x::text end;

  -- ------------------------------------------- 6) çok mağaza + Gel Al + bakiye
  select ub.balance into v_bal0 from public.user_balances ub where ub.user_id = v_u;
  v_s := pg_temp.prep(v_u, jsonb_build_array(
                        jsonb_build_object('product_id', v_pa, 'quantity', 1),
                        jsonb_build_object('product_id', v_pb, 'quantity', 2)),
                      v_addr, 'balance', 'parity-multi-0001', p_pickups => array[v_shop_a]);
  r := r || chr(10) || case when v_s->>'error' is null
        and (v_s->>'server_subtotal')::numeric = 300 and (v_s->>'server_delivery_fee')::numeric = 15
        and (v_s->>'server_total')::numeric = 315 and jsonb_array_length(v_s->'sub_orders') = 2
    then 'PASS cok magaza: A Gel Al (0 teslimat) + B 200 + 15 = 315'
    else 'FAIL cok magaza prepare ' || v_s::text end;

  v_c := pg_temp.commit(v_u, (v_s->>'session_id')::uuid, 'balance');
  select ub.balance into v_bal from public.user_balances ub where ub.user_id = v_u;
  select count(*) into v_cnt from public.orders o
   where o.checkout_session_id = (v_s->>'session_id')::uuid
     and o.payment_method::text = 'balance' and o.payment_status::text = 'paid'
     and o.order_group_id = (v_c->>'order_group_id') and o.group_order_number = v_c->>'group_order_number'
     and o.group_order_number like 'GRP%';
  r := r || chr(10) || case when v_c->>'error' is null and (v_c->>'order_count')::int = 2
        and v_cnt = 2 and v_bal = v_bal0 - 315 and (v_c->>'new_balance')::numeric = v_bal
    then 'PASS bakiye: 2 siparis odendi, bakiyeden 315 dustu, grup no ortak'
    else format('FAIL bakiye commit cnt=%s bal0=%s bal=%s %s', v_cnt, v_bal0, v_bal, v_c) end;

  select o.* into v_o from public.orders o
   where o.checkout_session_id = (v_s->>'session_id')::uuid and o.shop_id = v_shop_a;
  r := r || chr(10) || case when v_o.is_pickup and v_o.delivery_fee = 0 and v_o.total = 100
        and v_o.delivery_address_text = 'Gel Al - Mağazadan Teslim'
    then 'PASS Gel Al siparisi teslimatsiz ve pickup isaretli'
    else 'FAIL Gel Al siparisi ' || coalesce(to_jsonb(v_o)::text, 'yok') end;

  select o.* into v_o from public.orders o
   where o.checkout_session_id = (v_s->>'session_id')::uuid and o.shop_id = v_shop_b;
  r := r || chr(10) || case when not v_o.is_pickup and v_o.delivery_fee = 15 and v_o.total = 215
        and v_o.delivery_address_text = 'Ev - Cudi Mah. 1. Sok, No 5, Merkez, Cizre, 73200'
    then 'PASS cok magaza teslimat metni eski akisla ayni (baslik - adres)'
    else 'FAIL magaza B siparisi ' || coalesce(to_jsonb(v_o)::text, 'yok') end;

  select count(*) into v_cnt from public.balance_transactions bt
   where bt.user_id = v_u and bt.reference_type = 'order' and bt.type = 'order_payment'
     and bt.reference_id in (select o.id from public.orders o
                              where o.checkout_session_id = (v_s->>'session_id')::uuid);
  r := r || chr(10) || case when v_cnt = 2
    then 'PASS bakiye defteri siparis kimligiyle yazildi (iade bulur)'
    else format('FAIL defter kaydi sayisi=%s', v_cnt) end;

  update public.user_balances set balance = 50 where user_id = v_u;
  v_s := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'balance', 'parity-poor-0001');
  v_x := pg_temp.commit(v_u, (v_s->>'session_id')::uuid, 'balance');
  select count(*) into v_cnt from public.orders o where o.checkout_session_id = (v_s->>'session_id')::uuid;
  r := r || chr(10) || case when v_x->>'error' like 'APP: insufficient_balance | Yetersiz bakiye! Mevcut: ₺50.00, Gerekli: ₺115.00%'
        and v_cnt = 0
        and (select ub.balance from public.user_balances ub where ub.user_id = v_u) = 50
    then 'PASS yetersiz bakiye: siparis acilmadi, bakiye degismedi'
    else format('FAIL yetersiz bakiye cnt=%s %s', v_cnt, v_x) end;
  update public.user_balances set balance = 1000 where user_id = v_u;

  -- ------------------------------------------- 7) flaş: sepet talebi + rezervasyon
  insert into public.flash_sales (product_id, shop_id, original_price, flash_price, stock_limit,
                                  sold_count, start_at, end_at, is_active, created_by)
  values (v_pa, v_shop_a, 100, 80, 3, 0, now() - interval '1 hour', now() + interval '1 hour', true, v_owner_a)
  returning id into v_sale;

  v_x := pg_temp.as_user(v_u, format('select public.claim_flash_sale(%L::uuid, 2, null)', v_sale));
  select f.sold_count into v_sold from public.flash_sales f where f.id = v_sale;
  r := r || chr(10) || case when (v_x->>'success')::boolean and v_sold = 2
    then 'PASS sepete ekleme talebi sold_count=2'
    else format('FAIL claim %s sold=%s', v_x, v_sold) end;

  v_s := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 2, 'flash_sale_id', v_sale)),
                      v_addr, 'cash', 'parity-flash-0001');
  v_sid := (v_s->>'session_id')::uuid;
  r := r || chr(10) || case when v_s->>'error' is null and (v_s->>'server_subtotal')::numeric = 160
        and (select count(*) from private.flash_sale_reservations fr
              where fr.session_id = v_sid and fr.sale_id = v_sale and fr.quantity = 2 and fr.status = 'active') = 1
    then 'PASS flas: 80 TL fiyat + oturuma bagli rezervasyon (kendi talebi stok sayildi)'
    else 'FAIL flas prepare ' || v_s::text end;

  v_x := pg_temp.prep(v_u2, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 2, 'flash_sale_id', v_sale)),
                      v_addr2, 'cash', 'parity-flash-0002');
  r := r || chr(10) || case when v_x->>'error' like 'APP: flash_stock%'
    then 'PASS rezervasyon + talep stogu baskasina karsi tuttu'
    else 'FAIL flas asiri satis ' || v_x::text end;

  v_c := pg_temp.commit(v_u, v_sid, 'cod');
  v_oid := (v_c->>'order_id')::uuid;
  select f.sold_count into v_sold from public.flash_sales f where f.id = v_sale;
  select c.quantity into v_mine from private.flash_sale_claims c where c.user_id = v_u and c.sale_id = v_sale;
  r := r || chr(10) || case when v_sold = 2 and coalesce(v_mine, 0) = 0
        and (select fr.status from private.flash_sale_reservations fr where fr.session_id = v_sid) = 'committed'
        and (select count(*) from public.order_items oi
              where oi.order_id = v_oid and oi.flash_sale_id = v_sale and oi.price = 80) = 1
    then 'PASS commit talebi tuketti, satis bir kez sayildi (sold=2)'
    else format('FAIL flas commit sold=%s mine=%s %s', v_sold, v_mine, v_c) end;

  v_x := pg_temp.as_user(v_u, format('select public.release_flash_sale(%L::uuid, 2)', v_sale));
  select f.sold_count into v_sold from public.flash_sales f where f.id = v_sale;
  r := r || chr(10) || case when v_sold = 2
    then 'PASS eski surumun clearCart release cagrisi satilani geri vermedi'
    else format('FAIL release sonrasi sold=%s', v_sold) end;

  v_s := pg_temp.prep(v_u2, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1, 'flash_sale_id', v_sale)),
                      v_addr2, 'cash', 'parity-flash-0003');
  v_x := pg_temp.as_user(v_u2, format('select to_jsonb(public.cancel_checkout_session(%L::uuid))', v_s->>'session_id'));
  r := r || chr(10) || case when v_x = 'true'::jsonb
        and (select fr.status from private.flash_sale_reservations fr
              where fr.session_id = (v_s->>'session_id')::uuid) = 'released'
        and (select ss.status from private.server_checkout_sessions ss
              where ss.id = (v_s->>'session_id')::uuid) = 'cancelled'
    then 'PASS onay penceresi kapaninca rezervasyon birakildi'
    else 'FAIL cancel ' || coalesce(v_x::text, 'null') end;

  v_s := pg_temp.prep(v_u2, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1, 'flash_sale_id', v_sale)),
                      v_addr2, 'cash', 'parity-flash-0004');
  v_c := pg_temp.commit(v_u2, (v_s->>'session_id')::uuid, 'cod');
  select f.sold_count into v_sold from public.flash_sales f where f.id = v_sale;
  r := r || chr(10) || case when v_c->>'error' is null and v_sold = 3
    then 'PASS talepsiz flas satisi commit aninda sayildi (sold=3)'
    else format('FAIL talepsiz flas sold=%s %s', v_sold, v_c) end;

  update public.orders set status = 'cancelled' where id = v_oid;
  select f.sold_count into v_sold from public.flash_sales f where f.id = v_sale;
  select c.quantity into v_mine from private.flash_sale_claims c where c.user_id = v_u and c.sale_id = v_sale;
  r := r || chr(10) || case when v_sold = 1 and coalesce(v_mine, 0) = 0
    then 'PASS oturumlu siparis iptali flas adedini stoga dondurdu'
    else format('FAIL iptal sold=%s mine=%s', v_sold, v_mine) end;

  update public.flash_sales set end_at = now() - interval '1 second', start_at = now() - interval '2 hours'
   where id = v_sale;
  v_s := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1, 'flash_sale_id', v_sale)),
                      v_addr, 'cash', 'parity-flash-0005');
  r := r || chr(10) || case when (v_s->>'server_subtotal')::numeric = 100
        and v_s->'warnings'->0->>'code' = 'flash_ended'
    then 'PASS biten flas normal fiyata dondu ve uyari verdi'
    else 'FAIL biten flas ' || v_s::text end;

  -- ------------------------------------------- 8) online: iyzico geri çağrısı
  v_s := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'online', 'parity-online-0001');
  v_sid := (v_s->>'session_id')::uuid;
  insert into public.payment_transactions (user_id, conversation_id, amount, currency, payment_status,
         paid_price, payment_id, checkout_session_id, callback_data)
  values (v_u, 'parity_conv', 115, 'TRY', 'success', 115, 'parity_pay_1', v_sid,
          jsonb_build_object('checkout_session_id', v_sid, 'user_id', v_u))
  returning id into v_txn;

  v_oid := public.complete_online_payment(v_txn);
  select o.* into v_o from public.orders o where o.id = v_oid;
  r := r || chr(10) || case when v_o.payment_method::text = 'online' and v_o.payment_status::text = 'paid'
        and v_o.total = 115 and v_o.payment_transaction_id = v_txn and v_o.checkout_session_id = v_sid
        and v_o.iyzico_payment_id = 'parity_pay_1' and not v_o.price_mismatch
        and (select pt.order_id from public.payment_transactions pt where pt.id = v_txn) = v_oid
        and (select ss.status from private.server_checkout_sessions ss where ss.id = v_sid) = 'committed'
    then 'PASS online: geri cagri oturumdan odenmis siparis acti'
    else 'FAIL online ' || coalesce(to_jsonb(v_o)::text, 'siparis yok') end;

  r := r || chr(10) || case when public.complete_online_payment(v_txn) = v_oid
        and (select count(*) from public.orders o where o.checkout_session_id = v_sid) = 1
    then 'PASS online geri cagri tekrar gelince ayni siparis'
    else 'FAIL online tekrar' end;

  v_s := pg_temp.prep(v_u, jsonb_build_array(jsonb_build_object('product_id', v_pa, 'quantity', 1)),
                      v_addr, 'online', 'parity-online-0002');
  insert into public.payment_transactions (user_id, conversation_id, amount, currency, payment_status,
         paid_price, payment_id, checkout_session_id, callback_data)
  values (v_u, 'parity_conv2', 115, 'TRY', 'success', 90, 'parity_pay_2', (v_s->>'session_id')::uuid,
          jsonb_build_object('checkout_session_id', v_s->>'session_id', 'user_id', v_u))
  returning id into v_txn;
  update private.server_checkout_sessions set expires_at = now() - interval '5 minutes'
   where id = (v_s->>'session_id')::uuid;
  v_oid := public.complete_online_payment(v_txn);
  r := r || chr(10) || case when (select o.price_mismatch from public.orders o where o.id = v_oid)
    then 'PASS eksik odeme: siparis acildi ama price_mismatch isaretlendi (suresi dolsa da)'
    else 'FAIL eksik odeme isareti' end;

  -- ------------------------------------------- 9) yetki
  select (has_function_privilege('anon', 'public.prepare_checkout_session(jsonb, uuid, text, text, uuid, text, text, jsonb, uuid, uuid[], uuid[])', 'execute')
      or has_function_privilege('authenticated', 'public.commit_online_order(uuid)', 'execute')
      or has_function_privilege('authenticated', 'public.get_checkout_session_for_payment(uuid, uuid)', 'execute')
      or has_function_privilege('authenticated', 'private.checkout_create_orders(uuid, text, text, boolean, boolean, uuid, text, text, boolean)', 'execute'))::int
    into v_cnt;
  r := r || chr(10) || case when v_cnt = 0
    then 'PASS anon/istemci ic fonksiyonlari cagiramiyor'
    else 'FAIL yetki sizintisi' end;

  insert into _parity_results(line) values (r);
end
$test$;

SELECT string_agg(line, E'\n' ORDER BY n) AS result FROM _parity_results;

ROLLBACK;
