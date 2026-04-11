-- ============================================================================
-- ONLINE ÖDEME SİSTEMİ - DÜZELTMELER
-- ============================================================================
-- complete_online_payment fonksiyonunu sipariş oluşturma akışına uygun hale getir
-- Tarih: 2026-02-12

-- ============================================================================
-- 1. complete_online_payment FONKSİYONUNU GÜNCELLE
-- ============================================================================
-- Eski versiyonu drop et
DROP FUNCTION IF EXISTS public.complete_online_payment(UUID, VARCHAR, UUID);

-- Yeni versiyon: callback_data'dan sipariş oluşturur
CREATE OR REPLACE FUNCTION public.complete_online_payment(
  p_payment_transaction_id UUID
)
RETURNS UUID -- oluşturulan order_id'yi döner
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
  v_coupon_id UUID;
  v_delivery_address_text TEXT;
  v_delivery_address_id UUID;
  v_note TEXT;
BEGIN
  -- 1. Payment transaction'ı al
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
    RAISE EXCEPTION 'Sipariş verileri eksik (callback_data)';
  END IF;

  v_shop_id := (v_order_data ->> 'shop_id')::UUID;
  v_total := (v_order_data ->> 'total')::DECIMAL;
  v_subtotal := (v_order_data ->> 'subtotal')::DECIMAL;
  v_delivery_fee := COALESCE((v_order_data ->> 'delivery_fee')::DECIMAL, 0);
  v_coupon_discount := COALESCE((v_order_data ->> 'coupon_discount')::DECIMAL, 0);
  v_delivery_address_text := v_order_data ->> 'delivery_address_text';
  v_note := v_order_data ->> 'note';
  v_items := v_order_data -> 'items';
  
  -- Coupon ID opsiyonel
  IF v_order_data ->> 'coupon_id' IS NOT NULL AND v_order_data ->> 'coupon_id' != '' THEN
    v_coupon_id := (v_order_data ->> 'coupon_id')::UUID;
  END IF;
  
  -- Delivery address ID opsiyonel
  IF v_order_data ->> 'delivery_address_id' IS NOT NULL AND v_order_data ->> 'delivery_address_id' != '' THEN
    v_delivery_address_id := (v_order_data ->> 'delivery_address_id')::UUID;
  END IF;
  
  -- 3. Sipariş numarası oluştur
  v_order_number := 'ONL-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || 
                    LPAD(FLOOR(RANDOM() * 99999)::TEXT, 5, '0');

  -- 4. Siparişi oluştur
  INSERT INTO public.orders (
    user_id,
    shop_id,
    order_number,
    status,
    payment_method,
    payment_status,
    total_amount,
    subtotal,
    delivery_fee,
    coupon_discount,
    coupon_id,
    delivery_address,
    delivery_address_id,
    note,
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
    v_coupon_id,
    v_delivery_address_text,
    v_delivery_address_id,
    v_note,
    p_payment_transaction_id,
    v_payment_record.payment_id,
    v_payment_record.conversation_id
  )
  RETURNING id INTO v_order_id;

  -- 5. Sipariş kalemlerini oluştur
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
  LOOP
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price,
      variant_data
    ) VALUES (
      v_order_id,
      (v_item ->> 'product_id')::UUID,
      v_item ->> 'product_name',
      (v_item ->> 'quantity')::INTEGER,
      (v_item ->> 'price')::DECIMAL,
      CASE 
        WHEN v_item -> 'variant_data' IS NOT NULL THEN v_item -> 'variant_data'
        ELSE NULL
      END
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
  'iyzico ödeme başarılı callback sonrası siparişi oluşturur. callback_data içindeki order bilgilerini kullanır.';

DO $$
BEGIN
    RAISE NOTICE '✅ complete_online_payment fonksiyonu güncellendi - artık sipariş oluşturuyor';
END $$;
