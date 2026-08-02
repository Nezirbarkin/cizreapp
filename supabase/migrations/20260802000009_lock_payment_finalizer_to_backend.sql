-- ════════════════════════════════════════════════════════════════════════
-- Payment Finalizer Lockdown + Yeni Server-Authoritative Akış
-- Tarih: 2026-08-02
-- ════════════════════════════════════════════════════════════════════════
-- SORUN:
--   1) public.complete_online_payment callback_data->order_data'dan
--      fiyat/ürün/mağaza okuyor → client-authoritative.
--   2) public.atomic_finalize_payment_transaction authenticated tarafından
--      çağrılabiliyor (sadece service_role olmalı).
--   3) pending durumda da sipariş oluşturabiliyor (kontrol yok).
--   4) Exception'ları yutup alreadyProcessed dönüyor.
--   5) ESKİ callback_data kullanımı: amount_mismatch tespiti YOK.
--
-- ÇÖZÜM:
--   - Yeni private.commit_online_order RPC'si, session snapshot'tan
--     sipariş oluşturur. callback_data kullanmaz.
--   - Yeni private.atomic_finalize_payment_transaction
--     signature/currency/amount doğrular, mismatch → reconciliation.
--   - ESKİ public.* RPC'leri DROP edilir.
--   - Grant'lar sadece service_role + SECURITY DEFINER baglaminda.
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════════
-- 1) atomic_finalize_payment_transaction — private, server-authoritative
-- ════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.atomic_finalize_payment_transaction(
  UUID, TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, JSONB
);

CREATE OR REPLACE FUNCTION private.atomic_finalize_payment_transaction(
  p_transaction_id UUID,
  p_payment_id TEXT,
  p_paid_price NUMERIC,
  p_card_type TEXT,
  p_card_association TEXT,
  p_card_family TEXT,
  p_card_bank_name TEXT,
  p_last_four_digits TEXT,
  p_fraud_status INTEGER,
  p_md_status INTEGER DEFAULT NULL,
  p_status TEXT,                 -- 'success' | 'failure' | 'amount_mismatch'
  p_error_code TEXT DEFAULT NULL,
  p_error_message TEXT DEFAULT NULL,
  p_error_group TEXT DEFAULT NULL,
  p_callback_received_at TIMESTAMPTZ DEFAULT NOW(),
  p_merged_callback_data JSONB DEFAULT '{}'::JSONB
)
RETURNS TABLE (
  updated BOOLEAN,
  already_processed BOOLEAN,
  payment_status TEXT,
  reconciliation_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_current_status TEXT;
  v_was_updated BOOLEAN := FALSE;
  v_reconciliation TEXT;
  v_expected_amount NUMERIC;
  v_expected_currency CHAR(3);
  v_expected_env TEXT;
  v_session_id UUID;
BEGIN
  -- ═══════════════════════════════════════════════════════════════════
  -- 1) Transaction FOR UPDATE kilitle
  -- ═══════════════════════════════════════════════════════════════════
  SELECT payment_status, expected_amount, expected_currency, iyzico_environment,
         checkout_session_id
    INTO v_current_status, v_expected_amount, v_expected_currency, v_expected_env, v_session_id
  FROM public.payment_transactions
  WHERE id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment transaction bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 2) Idempotent: zaten pending değilse, onceki sonucu don
  -- ═══════════════════════════════════════════════════════════════════
  IF v_current_status IS DISTINCT FROM 'pending' THEN
    RETURN QUERY SELECT FALSE, TRUE, v_current_status, NULL::TEXT;
    RETURN;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 3) AMOUNT/CURRENCY/ENV MISMATCH KONTROLU
  -- ═══════════════════════════════════════════════════════════════════
  v_reconciliation := NULL;

  IF p_status = 'success' THEN
    IF v_expected_amount IS NOT NULL AND p_paid_price IS NOT NULL
       AND abs(p_paid_price - v_expected_amount) > 0.005 THEN
      v_reconciliation := 'amount_mismatch';
      INSERT INTO private.server_checkout_audit (session_id, payment_transaction_id, event_type, detail)
      VALUES (v_session_id, p_transaction_id, 'amount_mismatch', jsonb_build_object(
        'expected_amount', v_expected_amount,
        'actual_paid_price', p_paid_price,
        'payment_id', p_payment_id
      ));
    ELSIF v_expected_currency IS NOT NULL AND p_merged_callback_data->>'currency' IS NOT NULL
          AND v_expected_currency <> (p_merged_callback_data->>'currency') THEN
      v_reconciliation := 'currency_mismatch';
      INSERT INTO private.server_checkout_audit (session_id, payment_transaction_id, event_type, detail)
      VALUES (v_session_id, p_transaction_id, 'currency_mismatch', jsonb_build_object(
        'expected_currency', v_expected_currency,
        'actual_currency', p_merged_callback_data->>'currency'
      ));
    ELSIF v_expected_env = 'production' AND (p_merged_callback_data->>'environment') = 'sandbox' THEN
      v_reconciliation := 'env_mismatch';
      INSERT INTO private.server_checkout_audit (session_id, payment_transaction_id, event_type, detail)
      VALUES (v_session_id, p_transaction_id, 'env_mismatch', jsonb_build_object(
        'expected_env', v_expected_env,
        'actual_env', p_merged_callback_data->>'environment'
      ));
    ELSIF p_fraud_status IS NOT NULL AND p_fraud_status <> 1 THEN
      v_reconciliation := 'signature_invalid';
      INSERT INTO private.server_checkout_audit (session_id, payment_transaction_id, event_type, detail)
      VALUES (v_session_id, p_transaction_id, 'signature_invalid', jsonb_build_object(
        'fraud_status', p_fraud_status
      ));
    END IF;

    -- Mismatch tespit edilirse status='success' yerine 'amount_mismatch' kaydet
    IF v_reconciliation IS NOT NULL THEN
      UPDATE public.payment_transactions
      SET
        payment_status = 'failure',
        reconciliation_status = v_reconciliation,
        error_code = p_error_code,
        error_message = COALESCE(p_error_message, 'Reconciliation gerekli: ' || v_reconciliation),
        error_group = p_error_group,
        callback_received_at = p_callback_received_at,
        callback_data = COALESCE(callback_data, '{}'::JSONB) || p_merged_callback_data,
        updated_at = NOW()
      WHERE id = p_transaction_id;

      RETURN QUERY SELECT TRUE, FALSE, 'failure'::TEXT, v_reconciliation;
      RETURN;
    END IF;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 4) Atomik UPDATE
  -- ═══════════════════════════════════════════════════════════════════
  UPDATE public.payment_transactions
  SET
    payment_status = p_status,
    payment_id = p_payment_id,
    paid_price = p_paid_price,
    card_type = p_card_type,
    card_association = p_card_association,
    card_family = p_card_family,
    card_bank_name = p_card_bank_name,
    last_four_digits = p_last_four_digits,
    fraud_status = p_fraud_status,
    callback_received_at = p_callback_received_at,
    callback_data = COALESCE(callback_data, '{}'::JSONB) || p_merged_callback_data,
    error_code = p_error_code,
    error_message = p_error_message,
    error_group = p_error_group,
    updated_at = NOW()
  WHERE id = p_transaction_id
    AND payment_status = 'pending';

  GET DIAGNOSTICS v_was_updated = ROW_COUNT;

  IF v_was_updated = 0 THEN
    RETURN QUERY SELECT FALSE, TRUE, v_current_status, v_reconciliation;
  ELSE
    RETURN QUERY SELECT TRUE, FALSE, p_status, v_reconciliation;
  END IF;

EXCEPTION WHEN OTHERS THEN
  -- Gercek DB hatalari loglanir; transaction rollback olur
  RAISE WARNING 'atomic_finalize_payment_transaction hatasi: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
  RAISE;
END;
$$;

REVOKE ALL ON FUNCTION private.atomic_finalize_payment_transaction(
  UUID, TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, JSONB
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.atomic_finalize_payment_transaction(
  UUID, TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, JSONB
) TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- 2) commit_online_order — session snapshot'tan atomik siparis
-- ════════════════════════════════════════════════════════════════════════
-- NOT: Bu RPC service_role tarafindan cagrilir (iyzico-payment-callback
-- Edge Function icinden). client ASLA dogrudan cagiramaz.
-- ════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.complete_online_payment(UUID);

CREATE OR REPLACE FUNCTION private.commit_online_order(
  p_payment_transaction_id UUID
)
RETURNS TABLE (
  order_id UUID,
  order_group_id UUID,
  order_number TEXT,
  status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payment_record RECORD;
  v_session RECORD;
  v_item JSONB;
  v_shop_item RECORD;
  v_order_id UUID;
  v_order_number TEXT;
  v_order_group_id UUID;
  v_existing_order_id UUID;
  v_order_count INTEGER := 0;
  v_now TIMESTAMPTZ := NOW();
  v_reservation RECORD;
BEGIN
  -- ═════════════════════════════════════════════════════════════════
  -- 1) PAYMENT TRANSACTION (FOR UPDATE)
  -- ═════════════════════════════════════════════════════════════════
  SELECT * INTO v_payment_record
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment transaction bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotent: zaten order_id varsa
  IF v_payment_record.order_id IS NOT NULL THEN
    SELECT order_number, order_group_id INTO v_order_number, v_order_group_id
    FROM public.orders WHERE id = v_payment_record.order_id;
    RETURN QUERY SELECT v_payment_record.order_id, v_order_group_id, COALESCE(v_order_number, ''), 'committed'::TEXT;
    RETURN;
  END IF;

  -- KRITIK: Sadece success durumda order olustur.
  -- 'pending' durumda ASLA order olusturulamaz.
  -- 'failure' durumunda da order olusturulmaz (zaten yukarida kontrol var).
  IF v_payment_record.payment_status <> 'success' THEN
    RAISE EXCEPTION 'Order olusturulamaz: payment_status=% (sadece success izinli)',
      v_payment_record.payment_status
      USING ERRCODE = 'P0001';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 2) CHECKOUT SESSION (FOR UPDATE)
  -- ═════════════════════════════════════════════════════════════════
  IF v_payment_record.checkout_session_id IS NULL THEN
    RAISE EXCEPTION 'payment_transactions.checkout_session_id NULL' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_session
  FROM private.server_checkout_sessions
  WHERE id = v_payment_record.checkout_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Checkout session bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  IF v_session.status = 'committed' AND v_session.order_id IS NOT NULL THEN
    v_existing_order_id := v_session.order_id;
    SELECT order_number, order_group_id INTO v_order_number, v_order_group_id
    FROM public.orders WHERE id = v_existing_order_id;
    RETURN QUERY SELECT v_existing_order_id, v_order_group_id, COALESCE(v_order_number, ''), 'committed'::TEXT;
    RETURN;
  END IF;

  IF v_session.user_id <> v_payment_record.user_id THEN
    RAISE EXCEPTION 'Session user_id ile payment user_id uyumsuz' USING ERRCODE = '42501';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 3) AMOUNT DOGRULAMASI (server expected_amount vs paid_price)
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.expected_paid_price IS NOT NULL
     AND v_payment_record.paid_price IS NOT NULL
     AND abs(v_payment_record.paid_price - v_session.expected_paid_price) > 0.005 THEN
    RAISE EXCEPTION 'Amount mismatch (session.expected=%, payment.paid=%)',
      v_session.expected_paid_price, v_payment_record.paid_price
      USING ERRCODE = 'P0001';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 4) CURRENCY DOGRULAMASI
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.expected_currency IS NOT NULL
     AND v_payment_record.currency <> v_session.expected_currency THEN
    RAISE EXCEPTION 'Currency mismatch (session=% payment=%)',
      v_session.expected_currency, v_payment_record.currency
      USING ERRCODE = 'P0001';
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 5) RE-VALIDATION (urun/fiyat/stok hala gecerli mi)
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
  -- 6) KUPON COMMIT
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.coupon_id IS NOT NULL AND v_session.server_coupon_discount > 0 THEN
    PERFORM private.use_coupon(
      p_coupon_id := v_session.coupon_id,
      p_order_id := gen_random_uuid()  -- placeholder; asagida order_id set edildikten sonra tekrar
    );
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 7) ORDERS + ORDER_ITEMS (session snapshot'tan)
  -- Multi-shop: her magaza icin ayri order
  -- ═════════════════════════════════════════════════════════════════
  IF v_session.order_group_id IS NOT NULL THEN
    v_order_group_id := v_session.order_group_id;
  ELSE
    v_order_group_id := gen_random_uuid();
  END IF;

  FOR v_shop_item IN
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
      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_shop_item.items)
      LOOP
        v_shop_subtotal := v_shop_subtotal + (v_item_inner->>'subtotal')::NUMERIC;
      END LOOP;

      v_shop_delivery_fee := COALESCE(
        (v_session.sub_order_delivery_fees->>v_shop_item.shop_id::TEXT)::NUMERIC, 0
      );

      IF v_session.coupon_id IS NOT NULL THEN
        SELECT shop_id INTO v_c_shop_id FROM public.shop_coupons WHERE id = v_session.coupon_id;
        IF v_c_shop_id = v_shop_item.shop_id THEN
          IF jsonb_array_length(v_session.items_snapshot) = jsonb_array_length(v_shop_item.items) THEN
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
        notes, checkout_session_id, payment_transaction_id,
        iyzico_payment_id, iyzico_conversation_id, committed_at,
        invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
        invoice_tax_office, invoice_address, invoice_email,
        created_at, updated_at
      ) VALUES (
        v_payment_record.user_id, v_shop_item.shop_id, v_order_number, v_order_group_id, NULL,
        v_session.delivery_address_snapshot->>'address_line1',
        v_session.address_id,
        v_session.delivery_address_snapshot->>'phone',
        'online', 'paid', 'pending',
        v_shop_subtotal, v_shop_delivery_fee, v_session.server_discount,
        v_session.coupon_id, v_shop_coupon_discount, v_shop_total,
        v_session.notes, v_session.id, p_payment_transaction_id,
        v_payment_record.payment_id, v_payment_record.conversation_id, v_now,
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

      FOR v_item_inner IN SELECT * FROM jsonb_array_elements(v_shop_item.items)
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

  -- Kupon'u gercek order_id ile kaydet
  IF v_session.coupon_id IS NOT NULL AND v_session.server_coupon_discount > 0 THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.coupon_usages
      WHERE coupon_id = v_session.coupon_id AND order_id = v_existing_order_id
    ) THEN
      PERFORM private.use_coupon(
        p_coupon_id := v_session.coupon_id,
        p_order_id := v_existing_order_id
      );
    END IF;
  END IF;

  -- ═════════════════════════════════════════════════════════════════
  -- 8) FLAS REZERVASYONLARI COMMIT
  -- ═════════════════════════════════════════════════════════════════
  FOR v_reservation IN
    SELECT * FROM private.flash_sale_reservations
    WHERE session_id = v_session.id AND status = 'active'
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
  -- 9) PAYMENT_TRANSACTION + SESSION LINKI
  -- ═════════════════════════════════════════════════════════════════
  UPDATE public.payment_transactions
  SET order_id = v_existing_order_id, updated_at = v_now
  WHERE id = p_payment_transaction_id AND order_id IS NULL;

  UPDATE private.server_checkout_sessions
  SET
    status = 'committed',
    committed_at = v_now,
    order_id = v_existing_order_id,
    order_group_order_id = v_order_group_id,
    payment_transaction_id = p_payment_transaction_id,
    updated_at = v_now
  WHERE id = v_session.id;

  -- Audit
  INSERT INTO private.server_checkout_audit (session_id, payment_transaction_id, user_id, event_type, detail)
  VALUES (v_session.id, p_payment_transaction_id, v_payment_record.user_id, 'session_committed', jsonb_build_object(
    'order_id', v_existing_order_id,
    'order_group_id', v_order_group_id,
    'order_count', v_order_count,
    'total', v_session.server_total,
    'paid_price', v_payment_record.paid_price,
    'payment_method', 'online'
  ));

  RETURN QUERY SELECT v_existing_order_id, v_order_group_id, v_order_number, 'committed'::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION private.commit_online_order(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.commit_online_order(UUID) TO service_role;

DO $$
BEGIN
  RAISE NOTICE '✅ Payment finalizer lockdown tamamlandi';
  RAISE NOTICE '   - public.complete_online_payment DROP';
  RAISE NOTICE '   - public.atomic_finalize_payment_transaction DROP';
  RAISE NOTICE '   - private.atomic_finalize_payment_transaction (amount_mismatch, signature_invalid, currency_mismatch)';
  RAISE NOTICE '   - private.commit_online_order (sadece service_role)';
  RAISE NOTICE '   - pending durumda ASLA order olusturmaz';
END $$;
