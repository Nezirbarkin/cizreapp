-- =============================================================================
-- ROLLBACK: public.complete_online_payment geri yuklenir
--
-- NEDEN: 20260817000041 bu fonksiyonu dusurdu, ancak uygulamanin YAYINDAKI
-- surumu hala eski (Flow B) checkout akisini kullaniyor:
--   lib/features/shop/screens/checkout_screen.dart:266
--     -> lib/core/services/payment_service.dart:44-52
--        { user_id, order_data, buyer } gonderiyor
-- Yeni iyzico-payment-init ise { checkout_session_id, idempotency_key }
-- bekliyor ve aksi halde 400 donuyor. Yeni callback de siparisi
-- commit_online_order ile olusturuyor, o da checkout_session_id NULL olan
-- eski kayitlarda exception atiyor (para cekilir, siparis olusmaz).
--
-- Bu yuzden Edge Function'lar a97a422 surumune geri alindi ve onlarin
-- bagimli oldugu bu fonksiyon geri yuklendi.
--
-- Fonksiyon govdesi 20260801000002_complete_online_payment_coupon_id.sql
-- dosyasindan birebir alinmistir.
--
-- GUVENLIK NOTU: bu fonksiyon tutar/urun bilgisini
-- payment_transactions.callback_data->order_data icinden okur, yani
-- ISTEMCI-OTORITELIDIR. Gecici bir kurtarma adimidir. Kalici cozum
-- checkout ekranlarinin commit_online_order akisina tasinmasidir.
-- Bu nedenle EXECUTE yalnizca service_role'e verilir.
-- =============================================================================

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
  v_coupon_id UUID;
  v_delivery_address_text TEXT;
  v_delivery_address_id UUID;
  v_note TEXT;
  v_customer_phone TEXT;
  v_shop_name TEXT;
  v_existing_order_id UUID;
BEGIN
  -- IDEMPOTENT: Önce bu transaction için zaten oluşturulmuş order var mı?
  SELECT order_id INTO v_existing_order_id
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id;

  IF v_existing_order_id IS NOT NULL THEN
    RAISE NOTICE 'Sipariş zaten oluşturulmuş (idempotent): order_id=%', v_existing_order_id;
    RETURN v_existing_order_id;
  END IF;

  -- 1. Payment transaction'ı al
  SELECT * INTO v_payment_record
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment transaction bulunamadı: %', p_payment_transaction_id;
  END IF;

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
  -- coupon_id opsiyonel: boş string/null/eksik ise NULL bırak (kupon yok).
  -- NULLIF(..., '') boş string'i de yakalar; aksi halde ''::UUID exception fırlatır.
  v_coupon_id := NULLIF(v_order_data ->> 'coupon_id', '')::UUID;
  v_delivery_address_text := v_order_data ->> 'delivery_address_text';
  v_note := v_order_data ->> 'note';
  v_items := v_order_data -> 'items';
  v_customer_phone := v_order_data ->> 'customer_phone';

  SELECT name INTO v_shop_name FROM public.shops WHERE id = v_shop_id;

  IF v_order_data ->> 'delivery_address_id' IS NOT NULL AND v_order_data ->> 'delivery_address_id' != '' THEN
    v_delivery_address_id := (v_order_data ->> 'delivery_address_id')::UUID;
  END IF;

  -- 3. Sipariş numarası oluştur
  v_order_number := 'ONL-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
                    LPAD(FLOOR(RANDOM() * 99999)::TEXT, 5, '0');

  -- 4. Siparişi oluştur (coupon_id artık dahil)
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
    coupon_id,
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
    v_coupon_id,
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

  -- 5. Sipariş kalemlerini oluştur
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

  RAISE NOTICE 'Online sipariş oluşturuldu: order_id=%, order_number=%, coupon_id=%', v_order_id, v_order_number, v_coupon_id;

  RETURN v_order_id;
END;
$$;

-- Fonksiyon yeniden olusturuldugu icin ACL sifirlanir; 20260810000008'in
-- uyguladigi kisitlamayi tekrar uygula.
REVOKE ALL ON FUNCTION public.complete_online_payment(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_online_payment(UUID) TO service_role;

COMMENT ON FUNCTION public.complete_online_payment(UUID) IS
  'GECICI ROLLBACK (2026-08-17): yayindaki eski uygulama surumu icin geri yuklendi. Istemci-otoriteli; yalnizca service_role. Flow A cutover sonrasi tekrar dusurulmelidir.';

NOTIFY pgrst, 'reload schema';
