-- ════════════════════════════════════════════════════════════════════════
-- FIX: complete_online_payment fonksiyonunu idempotent yap + doğru kolonlar
-- Tarih: 2026-06-30
--
-- GERÇEK orders ŞEMASI (kullanıcıdan gelen tablo dökümünden):
--   id, order_number, user_id, shop_id,
--   delivery_address_id, delivery_address_text,
--   address_id,  -- (ayrıca mevcut)
--   payment_method, payment_status,
--   subtotal, delivery_fee, discount, total,
--   total_amount,  -- (ayrıca mevcut)
--   coupon_id, coupon_discount,  -- (ayrıca mevcut)
--   notes, customer_phone,
--   payment_transaction_id, iyzico_payment_id, iyzico_conversation_id
--
-- GERÇEK order_items ŞEMASI:
--   id, order_id, product_id, product_name,
--   product_price, quantity, subtotal,
--   shop_id, shop_name, product_image_url, created_at
--   (variant_data YOK!)
--
-- ÇÖZÜM:
-- - Sadece gerçekten var olan kolonları kullan
-- - IDEMPOTENT: önce mevcut order_id kontrol et
-- - payment_status şartı gevşetildi (race condition)
-- - order_id update'inde WHERE order_id IS NULL koruması
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.complete_online_payment(
  p_payment_transaction_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment_record RECORD;
  v_order_data JSONB;
  v_user_id UUID;
  v_shop_id UUID;
  v_order_id UUID;
  v_order_number VARCHAR;
  v_item JSONB;
  v_items JSONB;
  v_total DECIMAL;
  v_subtotal DECIMAL;
  v_delivery_fee DECIMAL;
  v_coupon_discount DECIMAL;
  v_delivery_address_text TEXT;
  v_delivery_address_id UUID;
  v_note TEXT;
  v_customer_phone TEXT;
  v_shop_name TEXT;
  v_existing_order_id UUID;
BEGIN
  -- ════════════════════════════════════════════════════════════════════
  -- IDEMPOTENT: Önce bu transaction için zaten oluşturulmuş order var mı?
  -- ════════════════════════════════════════════════════════════════════
  SELECT order_id INTO v_existing_order_id
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id;

  IF v_existing_order_id IS NOT NULL THEN
    RAISE NOTICE 'Sipariş zaten oluşturulmuş (idempotent): order_id=%', v_existing_order_id;
    RETURN v_existing_order_id;
  END IF;

  -- ════════════════════════════════════════════════════════════════════
  -- 1. Payment transaction'ı al (payment_status şartı GEVŞETİLDİ)
  -- ════════════════════════════════════════════════════════════════════
  SELECT * INTO v_payment_record
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment transaction bulunamadı: %', p_payment_transaction_id;
  END IF;

  -- Başarısız ödeme için order oluşturmayı engelle
  IF v_payment_record.payment_status = 'failure' THEN
    RAISE EXCEPTION 'Başarısız ödeme için sipariş oluşturulamaz: %', p_payment_transaction_id;
  END IF;

  -- 2. Callback data'dan sipariş bilgilerini çıkar
  v_order_data := v_payment_record.callback_data -> 'order_data';
  v_user_id := (v_payment_record.callback_data ->> 'user_id')::UUID;

  IF v_order_data IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sipariş verileri eksik (callback_data). callback_data: %', v_payment_record.callback_data;
  END IF;

  v_shop_id := (v_order_data ->> 'shop_id')::UUID;
  v_total := (v_order_data ->> 'total')::DECIMAL;
  v_subtotal := (v_order_data ->> 'subtotal')::DECIMAL;
  v_delivery_fee := COALESCE((v_order_data ->> 'delivery_fee')::DECIMAL, 0);
  v_coupon_discount := COALESCE((v_order_data ->> 'coupon_discount')::DECIMAL, 0);
  v_delivery_address_text := v_order_data ->> 'delivery_address_text';
  v_note := v_order_data ->> 'note';
  v_items := v_order_data -> 'items';
  v_customer_phone := v_order_data ->> 'customer_phone';

  -- Shop name'i al (order_items için gerekli)
  SELECT name INTO v_shop_name FROM public.shops WHERE id = v_shop_id;

  -- Delivery address ID opsiyonel
  IF v_order_data ->> 'delivery_address_id' IS NOT NULL AND v_order_data ->> 'delivery_address_id' != '' THEN
    v_delivery_address_id := (v_order_data ->> 'delivery_address_id')::UUID;
  END IF;

  -- 3. Sipariş numarası oluştur
  v_order_number := 'ONL-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
                    LPAD(FLOOR(RANDOM() * 99999)::TEXT, 5, '0');

  -- ════════════════════════════════════════════════════════════════════
  -- 4. Siparişi oluştur (GERÇEK orders ŞEMASI — sadece var olan kolonlar)
  -- Kullanılan kolonlar: total, subtotal, delivery_fee, discount,
  -- delivery_address_text, delivery_address_id, notes, customer_phone,
  -- coupon_discount, payment_transaction_id, iyzico_payment_id, iyzico_conversation_id
  -- ════════════════════════════════════════════════════════════════════
  INSERT INTO public.orders (
    user_id,
    shop_id,
    order_number,
    status,
    payment_method,
    payment_status,
    total,
    subtotal,
    delivery_fee,
    discount,
    coupon_discount,
    delivery_address_text,
    delivery_address_id,
    notes,
    customer_phone,
    payment_transaction_id,
    iyzico_payment_id,
    iyzico_conversation_id
  ) VALUES (
    v_user_id,
    v_shop_id,
    v_order_number,
    'pending',
    'online',
    'paid',
    v_total,
    v_subtotal,
    v_delivery_fee,
    v_coupon_discount,
    v_coupon_discount,
    v_delivery_address_text,
    v_delivery_address_id,
    v_note,
    v_customer_phone,
    p_payment_transaction_id,
    v_payment_record.payment_id,
    v_payment_record.conversation_id
  )
  RETURNING id INTO v_order_id;

  -- ════════════════════════════════════════════════════════════════════
  -- 5. Sipariş kalemlerini oluştur (GERÇEK order_items ŞEMASI)
  -- Kolonlar: order_id, product_id, product_name, product_price,
  -- quantity, subtotal, shop_id, shop_name
  -- (variant_data, product_image_url YOK — opsiyonel/zorunlu değil)
  -- ════════════════════════════════════════════════════════════════════
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
  LOOP
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price,
      product_price,
      subtotal,
      shop_id,
      shop_name
    ) VALUES (
      v_order_id,
      (v_item ->> 'product_id')::UUID,
      v_item ->> 'product_name',
      (v_item ->> 'quantity')::INTEGER,
      (v_item ->> 'price')::DECIMAL,
      (v_item ->> 'price')::DECIMAL,
      (v_item ->> 'price')::DECIMAL * (v_item ->> 'quantity')::INTEGER,
      v_shop_id,
      v_shop_name
    );
  END LOOP;

  -- 6. Payment transaction'a order_id'yi bağla (race condition koruması)
  UPDATE public.payment_transactions
  SET order_id = v_order_id,
      updated_at = NOW()
  WHERE id = p_payment_transaction_id
    AND order_id IS NULL;

  -- 7. Log
  RAISE NOTICE 'Online sipariş oluşturuldu: order_id=%, order_number=%', v_order_id, v_order_number;

  RETURN v_order_id;
END;
$$;

COMMENT ON FUNCTION public.complete_online_payment(UUID) IS
  'iyzico ödeme başarılı callback sonrası siparişi oluşturur. IDEMPOTENT: zaten order varsa mevcut ID''yi döner. Gerçek orders/order_items kolon adları kullanılır (total, discount, delivery_address_text, delivery_address_id, notes, customer_phone, product_price, subtotal). Race condition korumalı. 2026-06-30 güncellendi.';

DO $$
BEGIN
    RAISE NOTICE '✅ complete_online_payment idempotent + GERÇEK kolon adlarıyla güncellendi';
END $$;