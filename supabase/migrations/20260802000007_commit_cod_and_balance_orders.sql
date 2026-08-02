-- ════════════════════════════════════════════════════════════════════════
-- commit_cod_order + commit_balance_order RPC'leri
-- Tarih: 2026-08-02
-- ════════════════════════════════════════════════════════════════════════
-- Cash/card-on-delivery ve bakiye siparislerini server-checkout-session
-- snapshot'indan atomik olarak olusturur. Ayni transaction icinde:
--   1) Session FOR UPDATE kilitle
--   2) auth.uid() + status=pending + expires_at dogrula
--   3) Re-validation (fiyat, stok, kupon hala gecerli mi)
--   4) orders INSERT (server snapshot'tan, client-authoritative alan YOK)
--   5) order_items INSERT
--   6) [balance] user_balances UPDATE + balance_transactions INSERT (append-only ledger)
--   7) coupon_usages INSERT + shop_coupons.usage_count++ (FOR UPDATE)
--   8) flash_sale_reservations UPDATE status='committed' + flash_sales.sold_count++
--   9) server_checkout_sessions UPDATE status='completed', order_id
--   10) notification_outbox INSERT
-- Idempotent: ayni session_id ile iki kez commit = tek order.
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════════
-- 1) commit_cod_order
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION private.commit_cod_order(
  p_session_id UUID
)
RETURNS TABLE (
  order_id UUID,
  order_number TEXT,
  order_group_id UUID,
  status TEXT,
  total NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_session RECORD;
  v_item JSONB;
  v_order_id UUID;
  v_order_number TEXT;
  v_order_group_id UUID;
  v_existing_order_id UUID;
  v_order_count INTEGER := 0;
  v_now TIMESTAMPTZ := NOW();
  v_reservation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication gerekli' USING ERRCODE = '42501';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 1) SESSION KILITLE
  -- ═════════════════════════════════════════════════════════════════
  SELECT * INTO v_session
  FROM private.server_checkout_sessions
  WHERE id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 2) IDEMPOTENT: ayni session zaten commit edildiyse mevcut order'i don
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.status = 'committed' AND v_session.order_id IS NOT NULL THEN
    SELECT order_number INTO v_order_number FROM public.orders WHERE id = v_session.order_id;
    RETURN QUERY SELECT
      v_session.order_id, COALESCE(v_order_number, ''),
      v_session.order_group_id, 'committed'::TEXT, v_session.server_total;
    RETURN;
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 3) DOGRULAMALAR
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.user_id <> v_user_id THEN
    RAISE EXCEPTION 'Bu session bu kullaniciya ait degil' USING ERRCODE = '42501';
  END IF;

  IF v_session.status <> 'pending' THEN
    RAISE EXCEPTION 'Session zaten % durumunda', v_session.status USING ERRCODE = 'P0001';
  END IF;

  IF v_session.expires_at < v_now THEN
    UPDATE private.server_checkout_sessions
    SET status = 'expired', updated_at = v_now
    WHERE id = p_session_id;
    RAISE EXCEPTION 'Session suresi dolmus' USING ERRCODE = 'P0001';
  END IF;

  IF v_session.payment_method NOT IN ('cash','card_on_delivery') THEN
    RAISE EXCEPTION 'Bu RPC sadece cash/card_on_delivery icin. payment_method=%', v_session.payment_method
      USING ERRCODE = 'P0001';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 4) RE-VALIDATION: urun/fiyat hala gecerli mi?
  -- ═════════════════════════════════════════════════════════════════
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_session.items_snapshot)
  LOOP
    DECLARE
      v_current_price NUMERIC;
      v_current_stock INTEGER;
      v_is_available BOOLEAN;
    BEGIN
      SELECT
        COALESCE(p.discount_price, p.price),
        p.stock_quantity,
        p.is_available
      INTO v_current_price, v_current_stock, v_is_available
      FROM public.products p
      WHERE p.id = (v_item->>'product_id')::UUID;

      IF NOT FOUND OR NOT v_is_available THEN
        RAISE EXCEPTION 'Urun artik mevcut degil: %', v_item->>'product_id' USING ERRCODE = 'P0001';
      END IF;

      IF v_current_stock < (v_item->>'quantity')::INTEGER THEN
        RAISE EXCEPTION 'Stok yetersiz: %', v_item->>'product_id' USING ERRCODE = 'P0001';
      END IF;

      -- Flash satis ise fiyat kontrolu
      IF (v_item->>'flash_sale_id') IS NOT NULL THEN
        DECLARE
          v_flash RECORD;
        BEGIN
          SELECT fs.flash_price, fs.is_active, fs.start_at, fs.end_at,
                 fs.stock_limit, fs.sold_count
            INTO v_flash
          FROM public.flash_sales fs
          WHERE fs.id = (v_item->>'flash_sale_id')::UUID
            AND fs.is_active = true
          FOR UPDATE;

          IF NOT FOUND OR v_now NOT BETWEEN v_flash.start_at AND v_flash.end_at THEN
            RAISE EXCEPTION 'Flash satis artik gecerli degil' USING ERRCODE = 'P0001';
          END IF;
        END;
      END IF;
    END;
  END LOOP;

  -- ═════════════════════════════════════════════════════════════════
  -- 5) KUPON FOR UPDATE (commit aninda limit yeniden kontrol)
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.coupon_id IS NOT NULL THEN
    PERFORM 1
    FROM public.shop_coupons c
    WHERE c.id = v_session.coupon_id
      AND c.is_active = true
      AND (c.start_date IS NULL OR c.start_date <= v_now)
      AND (c.end_date IS NULL OR c.end_date >= v_now)
      AND (c.usage_limit IS NULL OR c.usage_count < c.usage_limit)
    FOR UPDATE OF c;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Kupon artik gecerli degil' USING ERRCODE = 'P0001';
    END IF;

    -- Kullanici basina limit
    IF EXISTS (
      SELECT 1 FROM public.shop_coupons
      WHERE id = v_session.coupon_id
        AND usage_per_user IS NOT NULL
        AND (
          SELECT COUNT(*) FROM public.coupon_usages
          WHERE coupon_id = v_session.coupon_id AND user_id = v_user_id
        ) >= usage_per_user
    ) THEN
      RAISE EXCEPTION 'Kullanici basina kupon limiti asildi' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 6) ORDERS + ORDER_ITEMS OLUSTUR
  -- Multi-shop ise her magaza icin ayri order
  -- ═════════════════════════════════════════════════════════════════
  -- Order group ID (multi-shop icin)
  IF v_session.order_group_id IS NOT NULL THEN
    v_order_group_id := v_session.order_group_id;
  ELSE
    v_order_group_id := gen_random_uuid();
  END IF;

  -- Snapshot'i magazalara gore grupla
  FOR v_item IN
    SELECT
      (e->>'shop_id')::UUID AS shop_id,
      (e->>'shop_name')::TEXT AS shop_name,
      jsonb_agg(e) AS items
    FROM jsonb_array_elements(v_session.items_snapshot) AS e
    GROUP BY (e->>'shop_id'), (e->>'shop_name')
  LOOP
    -- Per-shop subtotal (server)
    DECLARE
      v_shop_subtotal NUMERIC := 0;
      v_shop_delivery_fee NUMERIC := 0;
      v_shop_coupon_discount NUMERIC := 0;
      v_shop_total NUMERIC := 0;
      v_item_inner JSONB;
    BEGIN
      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_item.items)
      LOOP
        v_shop_subtotal := v_shop_subtotal + (v_item_inner->>'subtotal')::NUMERIC;
      END LOOP;

      v_shop_delivery_fee := COALESCE(
        (v_session.sub_order_delivery_fees->>v_item.shop_id::TEXT)::NUMERIC,
        0
      );

      -- Kupon magaza uyumu (cok magazali ise sadece cupona uyan magazaya uygula)
      IF v_session.coupon_id IS NOT NULL THEN
        DECLARE
          v_c_shop_id UUID;
        BEGIN
          SELECT shop_id INTO v_c_shop_id FROM public.shop_coupons WHERE id = v_session.coupon_id;
          IF v_c_shop_id = v_item.shop_id THEN
            -- Tek magazali ise toplam kupon; cok magazali ise sadece o magazaya
            IF jsonb_array_length(v_session.items_snapshot) = jsonb_array_length(v_item.items) THEN
              v_shop_coupon_discount := v_session.server_coupon_discount;
            ELSE
              v_shop_coupon_discount := 0; -- cok magaza cuponsuz hesap (detay icin ilerde)
            END IF;
          END IF;
        END;
      END IF;

      v_shop_total := v_shop_subtotal + v_shop_delivery_fee - v_shop_coupon_discount;

      v_order_number := 'ORD' || LPAD(nextval('order_number_seq')::TEXT, 8, '0');

      INSERT INTO public.orders (
        user_id, shop_id, order_number, order_group_id, group_order_number,
        delivery_address_text, address_id, customer_phone,
        payment_method, payment_status, status,
        subtotal, delivery_fee, discount, coupon_id, coupon_discount, total,
        notes, checkout_session_id, committed_at,
        invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
        invoice_tax_office, invoice_address, invoice_email,
        created_at, updated_at
      ) VALUES (
        v_user_id, v_item.shop_id, v_order_number, v_order_group_id, NULL,
        v_session.delivery_address_snapshot->>'address_line1',
        v_session.address_id,
        v_session.delivery_address_snapshot->>'phone',
        v_session.payment_method, 'pending', 'pending',
        v_shop_subtotal, v_shop_delivery_fee, v_session.server_discount,
        v_session.coupon_id, v_shop_coupon_discount, v_shop_total,
        v_session.notes, p_session_id, v_now,
        v_session.invoice_data->>'invoice_type',
        v_session.invoice_data->>'invoice_full_name',
        v_session.invoice_data->>'invoice_tax_number',
        v_session.invoice_data->>'invoice_tc_no',
        v_session.invoice_data->>'invoice_tax_office',
        v_session.invoice_data->>'invoice_address',
        v_session.invoice_data->>'invoice_email',
        v_now, v_now
      )
      RETURNING id INTO v_order_id;

      -- order_items INSERT
      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_item.items)
      LOOP
        INSERT INTO public.order_items (
          order_id, product_id, product_name, price, product_price, quantity, subtotal,
          product_image_url, shop_id, shop_name, flash_sale_id, flash_price,
          variant_data, created_at
        ) VALUES (
          v_order_id,
          (v_item_inner->>'product_id')::UUID,
          v_item_inner->>'product_name',
          (v_item_inner->>'unit_price')::NUMERIC,
          (v_item_inner->>'unit_price')::NUMERIC,
          (v_item_inner->>'quantity')::INTEGER,
          (v_item_inner->>'subtotal')::NUMERIC,
          v_item_inner->>'image_url',
          (v_item_inner->>'shop_id')::UUID,
          v_item_inner->>'shop_name',
          NULLIF(v_item_inner->>'flash_sale_id','')::UUID,
          NULLIF(v_item_inner->>'flash_price','')::NUMERIC,
          v_item_inner->'variant_data',
          v_now
        );
      END LOOP;

      IF v_order_count = 0 THEN
        v_existing_order_id := v_order_id; -- ilk order (multi-shop'ta ilk magaza)
      END IF;
      v_order_count := v_order_count + 1;
    END;
  END LOOP;

  -- Tek order mi cok order mi?
  IF v_order_count = 1 THEN
    v_existing_order_id := v_order_id;
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 7) KUPON KULLANIM KAYDI
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.coupon_id IS NOT NULL AND v_session.server_coupon_discount > 0 THEN
    -- Idempotency: ayni (coupon, order) zaten var mi?
    IF NOT EXISTS (
      SELECT 1 FROM public.coupon_usages
      WHERE coupon_id = v_session.coupon_id
        AND order_id = v_existing_order_id
    ) THEN
      INSERT INTO public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
      VALUES (v_session.coupon_id, v_existing_order_id, v_user_id, v_session.server_coupon_discount);

      UPDATE public.shop_coupons
      SET usage_count = usage_count + 1
      WHERE id = v_session.coupon_id;
    END IF;
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 8) FLAS REZERVASYONLARINI COMMIT ET
  -- ═════════════════════════════════════════════════════════════════
  FOR v_reservation IN
    SELECT * FROM private.flash_sale_reservations
    WHERE session_id = p_session_id AND status = 'active'
    FOR UPDATE
  LOOP
    -- sold_count artir (FOR UPDATE kilitle)
    UPDATE public.flash_sales
    SET sold_count = sold_count + v_reservation.quantity
    WHERE id = v_reservation.sale_id;

    UPDATE private.flash_sale_reservations
    SET status = 'committed', committed_at = v_now
    WHERE id = v_reservation.id;
  END LOOP;

  -- ═════════════════════════════════════════════════════════════════
  -- 9) SESSION COMPLETED
  -- ═════════════════════════════════════════════════════════════════
  UPDATE private.server_checkout_sessions
  SET
    status = 'committed',
    committed_at = v_now,
    order_id = v_existing_order_id,
    order_group_order_id = v_order_group_id,
    updated_at = v_now
  WHERE id = p_session_id;

  -- Audit
  INSERT INTO private.server_checkout_audit (session_id, user_id, event_type, detail)
  VALUES (p_session_id, v_user_id, 'session_committed', jsonb_build_object(
    'order_id', v_existing_order_id,
    'order_group_id', v_order_group_id,
    'order_count', v_order_count,
    'total', v_session.server_total
  ));

  RETURN QUERY SELECT
    v_existing_order_id,
    v_order_number,
    v_order_group_id,
    'committed'::TEXT,
    v_session.server_total;
END;
$$;

REVOKE ALL ON FUNCTION private.commit_cod_order(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.commit_cod_order(UUID) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════
-- 2) commit_balance_order (bakiye + siparis atomik)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION private.commit_balance_order(
  p_session_id UUID
)
RETURNS TABLE (
  order_id UUID,
  order_number TEXT,
  order_group_id UUID,
  status TEXT,
  total NUMERIC,
  balance_transaction_id UUID,
  new_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_session RECORD;
  v_item JSONB;
  v_order_id UUID;
  v_order_number TEXT;
  v_order_group_id UUID;
  v_existing_order_id UUID;
  v_order_count INTEGER := 0;
  v_now TIMESTAMPTZ := NOW();

  v_balance_id UUID;
  v_current_balance NUMERIC;
  v_balance_before NUMERIC;
  v_balance_after NUMERIC;
  v_balance_txn_id UUID;
  v_reservation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication gerekli' USING ERRCODE = '42501';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 1) SESSION KILITLE
  -- ═════════════════════════════════════════════════════════════════
  SELECT * INTO v_session
  FROM private.server_checkout_sessions
  WHERE id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotent
  IF v_session.status = 'committed' AND v_session.order_id IS NOT NULL THEN
    SELECT order_number INTO v_order_number FROM public.orders WHERE id = v_session.order_id;
    RETURN QUERY SELECT
      v_session.order_id, COALESCE(v_order_number, ''),
      v_session.order_group_id, 'committed'::TEXT, v_session.server_total,
      NULL::UUID, NULL::NUMERIC;
    RETURN;
  END IF;

  IF v_session.user_id <> v_user_id THEN
    RAISE EXCEPTION 'Bu session bu kullaniciya ait degil' USING ERRCODE = '42501';
  END IF;

  IF v_session.status <> 'pending' THEN
    RAISE EXCEPTION 'Session zaten % durumunda', v_session.status USING ERRCODE = 'P0001';
  END IF;

  IF v_session.expires_at < v_now THEN
    UPDATE private.server_checkout_sessions
    SET status = 'expired', updated_at = v_now
    WHERE id = p_session_id;
    RAISE EXCEPTION 'Session suresi dolmus' USING ERRCODE = 'P0001';
  END IF;

  IF v_session.payment_method <> 'balance' THEN
    RAISE EXCEPTION 'Bu RPC sadece balance icin. payment_method=%', v_session.payment_method
      USING ERRCODE = 'P0001';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 2) BAKIYE KILITLE + YETERLILIK KONTROLU
  -- ═════════════════════════════════════════════════════════════════
  SELECT id, balance INTO v_balance_id, v_current_balance
  FROM public.user_balances
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_balance_id IS NULL THEN
    RAISE EXCEPTION 'Bakiye kaydi bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  IF v_current_balance < v_session.server_total THEN
    RAISE EXCEPTION 'Yetersiz bakiye (mevcut: %, gerekli: %)',
      v_current_balance, v_session.server_total
      USING ERRCODE = 'P0001';
  END IF;

  v_balance_before := v_current_balance;
  v_balance_after := v_current_balance - v_session.server_total;

  -- ═════════════════════════════════════════════════════════════════
  -- 3) RE-VALIDATION: ayni cod_order'daki gibi
  -- ═════════════════════════════════════════════════════════════════
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_session.items_snapshot)
  LOOP
    DECLARE
      v_current_price NUMERIC;
      v_current_stock INTEGER;
      v_is_available BOOLEAN;
    BEGIN
      SELECT COALESCE(p.discount_price, p.price), p.stock_quantity, p.is_available
      INTO v_current_price, v_current_stock, v_is_available
      FROM public.products p
      WHERE p.id = (v_item->>'product_id')::UUID;

      IF NOT FOUND OR NOT v_is_available THEN
        RAISE EXCEPTION 'Urun artik mevcut degil: %', v_item->>'product_id' USING ERRCODE = 'P0001';
      END IF;

      IF v_current_stock < (v_item->>'quantity')::INTEGER THEN
        RAISE EXCEPTION 'Stok yetersiz: %', v_item->>'product_id' USING ERRCODE = 'P0001';
      END IF;
    END;
  END LOOP;

  -- ═════════════════════════════════════════════════════════════════
  -- 4) BAKIYE DUSUMU + LEDGER KAYDI (atomik)
  -- ═════════════════════════════════════════════════════════════════
  UPDATE public.user_balances
  SET balance = v_balance_after,
      total_spent = total_spent + v_session.server_total,
      updated_at = v_now
  WHERE id = v_balance_id;

  INSERT INTO public.balance_transactions (
    user_id, type, amount, net_amount,
    balance_before, balance_after,
    reference_type, reference_id, status, description, metadata,
    created_at, updated_at
  ) VALUES (
    v_user_id, 'order_payment', v_session.server_total, v_session.server_total,
    v_balance_before, v_balance_after,
    'order', gen_random_uuid(), 'completed',
    'Siparis odemesi (server checkout)',
    jsonb_build_object('session_id', p_session_id),
    v_now, v_now
  )
  RETURNING id INTO v_balance_txn_id;

  -- ═════════════════════════════════════════════════════════════════
  -- 5) ORDERS + ORDER_ITEMS (ayni commit_cod_order mantigi)
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.order_group_id IS NOT NULL THEN
    v_order_group_id := v_session.order_group_id;
  ELSE
    v_order_group_id := gen_random_uuid();
  END IF;

  FOR v_item IN
    SELECT
      (e->>'shop_id')::UUID AS shop_id,
      (e->>'shop_name')::TEXT AS shop_name,
      jsonb_agg(e) AS items
    FROM jsonb_array_elements(v_session.items_snapshot) AS e
    GROUP BY (e->>'shop_id'), (e->>'shop_name')
  LOOP
    DECLARE
      v_shop_subtotal NUMERIC := 0;
      v_shop_delivery_fee NUMERIC := 0;
      v_shop_coupon_discount NUMERIC := 0;
      v_shop_total NUMERIC := 0;
      v_item_inner JSONB;
      v_c_shop_id UUID;
    BEGIN
      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_item.items)
      LOOP
        v_shop_subtotal := v_shop_subtotal + (v_item_inner->>'subtotal')::NUMERIC;
      END LOOP;

      v_shop_delivery_fee := COALESCE(
        (v_session.sub_order_delivery_fees->>v_item.shop_id::TEXT)::NUMERIC, 0
      );

      IF v_session.coupon_id IS NOT NULL THEN
        SELECT shop_id INTO v_c_shop_id FROM public.shop_coupons WHERE id = v_session.coupon_id;
        IF v_c_shop_id = v_item.shop_id THEN
          IF jsonb_array_length(v_session.items_snapshot) = jsonb_array_length(v_item.items) THEN
            v_shop_coupon_discount := v_session.server_coupon_discount;
          END IF;
        END IF;
      END IF;

      v_shop_total := v_shop_subtotal + v_shop_delivery_fee - v_shop_coupon_discount;

      v_order_number := 'ORD' || LPAD(nextval('order_number_seq')::TEXT, 8, '0');

      INSERT INTO public.orders (
        user_id, shop_id, order_number, order_group_id, group_order_number,
        delivery_address_text, address_id, customer_phone,
        payment_method, payment_status, status,
        subtotal, delivery_fee, discount, coupon_id, coupon_discount, total,
        notes, checkout_session_id, committed_at,
        invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
        invoice_tax_office, invoice_address, invoice_email,
        created_at, updated_at
      ) VALUES (
        v_user_id, v_item.shop_id, v_order_number, v_order_group_id, NULL,
        v_session.delivery_address_snapshot->>'address_line1',
        v_session.address_id,
        v_session.delivery_address_snapshot->>'phone',
        'balance', 'paid', 'pending',
        v_shop_subtotal, v_shop_delivery_fee, v_session.server_discount,
        v_session.coupon_id, v_shop_coupon_discount, v_shop_total,
        v_session.notes, p_session_id, v_now,
        v_session.invoice_data->>'invoice_type',
        v_session.invoice_data->>'invoice_full_name',
        v_session.invoice_data->>'invoice_tax_number',
        v_session.invoice_data->>'invoice_tc_no',
        v_session.invoice_data->>'invoice_tax_office',
        v_session.invoice_data->>'invoice_address',
        v_session.invoice_data->>'invoice_email',
        v_now, v_now
      )
      RETURNING id INTO v_order_id;

      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_item.items)
      LOOP
        INSERT INTO public.order_items (
          order_id, product_id, product_name, price, product_price, quantity, subtotal,
          product_image_url, shop_id, shop_name, flash_sale_id, flash_price,
          variant_data, created_at
        ) VALUES (
          v_order_id,
          (v_item_inner->>'product_id')::UUID,
          v_item_inner->>'product_name',
          (v_item_inner->>'unit_price')::NUMERIC,
          (v_item_inner->>'unit_price')::NUMERIC,
          (v_item_inner->>'quantity')::INTEGER,
          (v_item_inner->>'subtotal')::NUMERIC,
          v_item_inner->>'image_url',
          (v_item_inner->>'shop_id')::UUID,
          v_item_inner->>'shop_name',
          NULLIF(v_item_inner->>'flash_sale_id','')::UUID,
          NULLIF(v_item_inner->>'flash_price','')::NUMERIC,
          v_item_inner->'variant_data',
          v_now
        );
      END LOOP;

      IF v_order_count = 0 THEN
        v_existing_order_id := v_order_id;
      END IF;
      v_order_count := v_order_count + 1;
    END;
  END LOOP;

  -- ═════════════════════════════════════════════════════════════════
  -- 6) KUPON KULLANIM KAYDI
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.coupon_id IS NOT NULL AND v_session.server_coupon_discount > 0 THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.coupon_usages
      WHERE coupon_id = v_session.coupon_id AND order_id = v_existing_order_id
    ) THEN
      INSERT INTO public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
      VALUES (v_session.coupon_id, v_existing_order_id, v_user_id, v_session.server_coupon_discount);

      UPDATE public.shop_coupons
      SET usage_count = usage_count + 1
      WHERE id = v_session.coupon_id;
    END IF;
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 7) FLAS REZERVASYONLARINI COMMIT ET
  -- ═════════════════════════════════════════════════════════════════
  FOR v_reservation IN
    SELECT * FROM private.flash_sale_reservations
    WHERE session_id = p_session_id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.flash_sales
    SET sold_count = sold_count + v_reservation.quantity
    WHERE id = v_reservation.sale_id;

    UPDATE private.flash_sale_reservations
    SET status = 'committed', committed_at = v_now
    WHERE id = v_reservation.id;
  END LOOP;

  -- ═════════════════════════════════════════════════════════════════
  -- 8) SESSION COMPLETED
  -- ═════════════════════════════════════════════════════════════════
  UPDATE private.server_checkout_sessions
  SET
    status = 'committed',
    committed_at = v_now,
    order_id = v_existing_order_id,
    order_group_order_id = v_order_group_id,
    updated_at = v_now
  WHERE id = p_session_id;

  -- Audit
  INSERT INTO private.server_checkout_audit (session_id, user_id, event_type, detail)
  VALUES (p_session_id, v_user_id, 'session_committed', jsonb_build_object(
    'order_id', v_existing_order_id,
    'payment_method', 'balance',
    'amount_deducted', v_session.server_total,
    'balance_txn_id', v_balance_txn_id
  ));

  RETURN QUERY SELECT
    v_existing_order_id,
    v_order_number,
    v_order_group_id,
    'committed'::TEXT,
    v_session.server_total,
    v_balance_txn_id,
    v_balance_after;
END;
$$;

REVOKE ALL ON FUNCTION private.commit_balance_order(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.commit_balance_order(UUID) TO authenticated;

DO $$
BEGIN
  RAISE NOTICE '✅ commit_cod_order + commit_balance_order RPC''leri olusturuldu';
  RAISE NOTICE '   - authenticated EXECUTE yetkisi';
  RAISE NOTICE '   - tum finansal islemler tek transaction icinde';
  RAISE NOTICE '   - idempotent (session_id ile tek order)';
END $$;
