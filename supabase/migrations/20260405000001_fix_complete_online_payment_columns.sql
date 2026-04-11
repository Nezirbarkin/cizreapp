-- ============================================================================
-- ONLINE ÖDEME - RPC FONKSİYONU SÜTUN ADLARI DÜZELTME (v2 - product_price eklendi)
-- ============================================================================
-- complete_online_payment fonksiyonundaki sütun adları orders tablosuyla uyuşmuyordu
-- Ayrıca order_items tablosunda product_price NOT NULL olduğu için insert başarısız oluyordu
-- Tarih: 2026-04-05

-- Eski versiyonu drop et
DROP FUNCTION IF EXISTS public.complete_online_payment(UUID);

-- Yeni versiyon: DOĞRU sütun adlarıyla
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
BEGIN
  -- 1. Payment transaction'ı al (hala success olmalı)
  SELECT * INTO v_payment_record
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id
    AND payment_status = 'success';
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment transaction bulunamadı veya başarılı değil: %', p_payment_transaction_id;
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

  -- 4. Siparişi oluştur (DOĞRU SÜTUN ADLARI)
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
    delivery_address_text,
    address_id,
    notes,
    payment_transaction_id,
    iyzico_payment_id,
    iyzico_conversation_id,
    customer_phone
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
    v_delivery_address_text,
    v_delivery_address_id,
    v_note,
    p_payment_transaction_id,
    v_payment_record.payment_id,
    v_payment_record.conversation_id,
    v_customer_phone
  )
  RETURNING id INTO v_order_id;

  -- 5. Sipariş kalemlerini oluştur (TÜM ZORUNLU SÜTUNLAR DAHİL)
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

  -- 6. Payment transaction'a order_id'yi bağla
  UPDATE public.payment_transactions
  SET order_id = v_order_id,
      updated_at = NOW()
  WHERE id = p_payment_transaction_id;

  -- 7. Log
  RAISE NOTICE 'Online sipariş oluşturuldu: order_id=%, order_number=%', v_order_id, v_order_number;

  RETURN v_order_id;
END;
$$;

COMMENT ON FUNCTION public.complete_online_payment(UUID) IS 
  'iyzico ödeme başarılı callback sonrası siparişi oluşturur. Sütun adları düzeltilmiş versiyon (v2 - product_price + shop_id/shop_name eklendi).';

DO $$
BEGIN
    RAISE NOTICE '✅ complete_online_payment fonksiyonu güncellendi - sütun adları düzeltildi (v2)';
END $$;
