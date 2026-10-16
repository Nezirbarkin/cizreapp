-- ============================================================================
-- Kupon satıcıdan düşülür + iade ile satıcıdan geri alınan pay (2026-10-16)
-- ----------------------------------------------------------------------------
-- Kuponlar satıcının kuponudur (orders.coupon_id → shop_coupons). Sipariş
-- toplamı = ara toplam − kupon + teslimat.
--   * Kuryeli satıcı: net = toplam − komisyon → kupon zaten satıcıdan
--     düşüyordu (değişmedi).
--   * Kuryesiz satıcı: net ara toplamdan hesaplandığı için kuponu PLATFORM
--     ödüyordu. Artık net = (toplam − müşterinin ödediği teslimat) − komisyon
--     − ücretsiz teslimat bedeli → kupon satıcıdan düşer.
--     Örnek: 100 ₺, 10 ₺ kupon, 15 ₺ teslimat, %10 → müşteri 105, satıcı 80.
--   * Komisyon değişmedi: kupon öncesi ara toplam üzerinden.
--
-- İade: müşteriye kuponlu (ödenen) tutar iade edilir — zaten böyleydi.
-- Satıcıdan geri alınan pay "net/toplam" oranıyla hesaplanıyordu; toplam
-- teslimat ücretini içerdiğinden kısmi iadede yanlış, kuryeli + online tam
-- iadede komisyon admine kalıyordu. Artık her talepte:
--   satıcıdan geri alınan = iade − iade edilen tutarın komisyonu.
-- ============================================================================

BEGIN;

-- ── 1) Komisyon hesabı ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_order_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_commission_rate NUMERIC;
  v_has_own_courier BOOLEAN;
  v_admin_commission NUMERIC;
  v_shop_delivery_fee NUMERIC;
  v_delivery_fee NUMERIC;
  v_seller_charge NUMERIC := 0;
BEGIN
  -- Satıcının bilgilerini al
  SELECT commission_rate, has_own_courier, delivery_fee
  INTO v_commission_rate, v_has_own_courier, v_shop_delivery_fee
  FROM public.shops
  WHERE id = NEW.shop_id;

  -- Varsayılan değerler
  v_has_own_courier := COALESCE(v_has_own_courier, FALSE);
  v_shop_delivery_fee := COALESCE(v_shop_delivery_fee, 0);
  v_delivery_fee := COALESCE(NEW.delivery_fee, v_shop_delivery_fee, 0);

  -- commission_rate normalizasyonu
  v_commission_rate := COALESCE(v_commission_rate, 10);
  IF v_commission_rate > 1 THEN
    v_commission_rate := v_commission_rate / 100;
  END IF;

  -- Komisyon hesapla (subtotal üzerinden)
  v_admin_commission := NEW.subtotal * v_commission_rate;

  -- Platform kuryesi + müşteriye ücretsiz teslimat: mağazanın teslimat
  -- ücreti satıcıdan kesilir. Admin müdahalesiyle ücret 0 ise kesinti yok.
  IF NOT v_has_own_courier
     AND NOT COALESCE(NEW.is_pickup, FALSE)
     AND v_delivery_fee = 0
     AND v_shop_delivery_fee > 0 THEN
    v_seller_charge := v_shop_delivery_fee;
  END IF;

  NEW.admin_commission := v_admin_commission;
  NEW.admin_delivery_fee := CASE WHEN v_has_own_courier THEN 0 ELSE v_delivery_fee + v_seller_charge END;
  NEW.seller_delivery_charge := v_seller_charge;
  NEW.seller_has_own_courier := v_has_own_courier;

  -- ====================================================================
  -- KURYESI OLAN SATICI
  -- ====================================================================
  IF v_has_own_courier THEN
    -- KAPIDA ÖDEMELER (cash, card_on_delivery, cardOnDelivery): Satıcı parayı alır, admin'e komisyon borcu
    IF NEW.payment_method IN ('cash', 'card_on_delivery', 'cardOnDelivery') THEN
      NEW.seller_cash_collected := NEW.total;
      NEW.seller_debt_amount := v_admin_commission;
      NEW.seller_credit_amount := 0;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'cash_collected';
    ELSE
      -- ONLINE ÖDEME: Admin parayı alır, satıcıya alacak
      NEW.seller_cash_collected := 0;
      NEW.seller_debt_amount := 0;
      NEW.seller_credit_amount := NEW.total - v_admin_commission;
      NEW.seller_net_amount := NEW.total - v_admin_commission;
      NEW.commission_status := 'admin_collects';
    END IF;
  ELSE
    -- ====================================================================
    -- KURYESI OLMAYAN SATICI
    -- ====================================================================
    -- Admin tüm parayı toplar. Satıcıya mal için ödenen (toplam − müşterinin
    -- ödediği teslimat; satıcı kuponu bu yüzden satıcıdan düşer) − komisyon
    -- − ücretsiz teslimat bedeli.
    NEW.seller_cash_collected := 0;
    NEW.seller_debt_amount := 0;
    NEW.seller_credit_amount := (NEW.total - v_delivery_fee) - v_admin_commission - v_seller_charge;
    NEW.seller_net_amount := (NEW.total - v_delivery_fee) - v_admin_commission - v_seller_charge;
    NEW.commission_status := 'admin_collects';
  END IF;

  RETURN NEW;
END;
$function$;

-- ── 2) İade onayı ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.approve_return_request(
  p_request_id     uuid,
  p_admin_response text DEFAULT NULL
) RETURNS public.return_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin       uuid := auth.uid();
  v_request     public.return_requests;
  v_order       record;
  v_goods_paid  numeric;
  v_commission  numeric;
  v_comm        numeric := 0;
  v_share       numeric;
  v_debit       numeric := 0;
  v_prev        numeric;
  v_final       boolean;
  v_shop        record;
  v_from        numeric;
  v_tx_id       uuid;
  v_label       text;
  v_note        text := NULLIF(btrim(COALESCE(p_admin_response, '')), '');
  v_item_count  integer;
  v_seller_cash boolean;
BEGIN
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request FROM public.return_requests
   WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'İade talebi bulunamadı' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'Bu talep zaten % durumunda, tekrar işlenemez', v_request.status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT id, shop_id, user_id, status::text AS status, payment_status::text AS payment_status,
         payment_method::text AS payment_method, commission_status::text AS commission_status,
         total, delivery_fee, admin_commission, seller_net_amount, order_number,
         COALESCE(seller_delivery_charge, 0) AS seller_delivery_charge
    INTO v_order
    FROM public.orders WHERE id = v_request.order_id FOR UPDATE;

  IF NOT FOUND OR v_order.status <> 'delivered' THEN
    RAISE EXCEPTION 'Sipariş artık teslim edilmiş durumda değil (iptal edilmiş olabilir); talebi reddedin'
      USING ERRCODE = 'P0001';
  END IF;
  IF v_order.payment_status = 'refunded' THEN
    RAISE EXCEPTION 'Bu siparişin ödemesi zaten iade edilmiş; talebi reddedin' USING ERRCODE = 'P0001';
  END IF;

  v_label       := COALESCE(v_order.order_number::text, substring(v_order.id::text, 1, 8));
  v_seller_cash := v_request.refund_method = 'seller_cash';
  v_goods_paid  := GREATEST(COALESCE(v_order.total, 0) - COALESCE(v_order.delivery_fee, 0), 0);
  -- Siparişte platformun aldığı komisyon (yoksa toplam − satıcı neti).
  v_commission  := GREATEST(COALESCE(v_order.admin_commission,
                                     COALESCE(v_order.total, 0)
                                       - COALESCE(v_order.seller_net_amount, v_order.total)), 0);

  -- Bu talep onaylanınca siparişte iade edilmemiş ürün kalıyor mu?
  v_final := NOT EXISTS (
    SELECT 1 FROM public.order_items oi
     WHERE oi.order_id = v_order.id
       AND oi.quantity > public.return_reserved_quantity(oi.id)
  );

  -- İade edilen tutarın komisyonu (admin bu kısmın komisyonunu almaz)
  IF v_request.refund_amount > 0 AND v_goods_paid > 0 THEN
    SELECT COALESCE(sum(commission_refund_amount), 0) INTO v_prev
      FROM public.return_requests
     WHERE order_id = v_order.id AND status IN ('approved', 'completed');
    IF v_final THEN
      v_comm := GREATEST(v_commission - v_prev, 0);
    ELSE
      v_comm := LEAST(round(v_request.refund_amount * v_commission / v_goods_paid, 2),
                      GREATEST(v_commission - v_prev, 0));
    END IF;
  END IF;

  SELECT id, owner_id, COALESCE(admin_credit, 0) AS admin_credit,
         COALESCE(commission_debt, 0) AS commission_debt
    INTO v_shop FROM public.shops WHERE id = v_order.shop_id FOR UPDATE;

  IF v_seller_cash THEN
    -- Kuryeli satıcı + kapıda ödeme: para satıcıda. Müşteriye nakdi satıcı
    -- iade eder; platform bakiyeye iade yapmaz. Satıcının komisyon borcu
    -- iade edilen tutarın komisyonu kadar azalır (borç yetmezse kalan,
    -- platformun satıcıya alacağı olur).
    IF FOUND AND (v_comm > 0 OR v_request.refund_amount > 0) THEN
      v_from := LEAST(GREATEST(v_shop.commission_debt, 0), v_comm);
      UPDATE public.shops
         SET commission_debt      = COALESCE(commission_debt, 0) - v_from,
             admin_credit         = COALESCE(admin_credit, 0) + (v_comm - v_from),
             total_collected_cash = GREATEST(COALESCE(total_collected_cash, 0) - v_request.refund_amount, 0),
             cash_payment_revenue = GREATEST(COALESCE(cash_payment_revenue, 0)
                                             - (v_request.refund_amount - v_comm), 0),
             updated_at           = now()
       WHERE id = v_shop.id;
    END IF;
  ELSE
    -- 1) Müşteriye bakiye iadesi
    IF v_request.refund_amount > 0 THEN
      v_tx_id := public.add_to_balance(
        p_user_id        := v_request.user_id,
        p_amount         := v_request.refund_amount,
        p_type           := 'refund'::public.balance_transaction_type,
        p_reference_type := 'return_request',
        p_reference_id   := v_request.id,
        p_description    := 'Ürün iadesi - Sipariş #' || v_label,
        p_payment_method := 'balance',
        p_metadata       := jsonb_build_object(
                              'source', 'return_request',
                              'approved_by', v_admin,
                              'order_id', v_order.id,
                              'return_scope', v_request.return_scope,
                              'original_payment_method', v_order.payment_method)
      );
    END IF;

    -- 2) Satıcıdan geri alınan = iade tutarı − o tutarın komisyonu.
    --    İade tutarı kuponlu (müşterinin gerçekten ödediği) mal bedelidir;
    --    teslimat ücreti ve ücretsiz teslimat bedeli bu hesaba girmez
    --    (teslimat yapıldı). Siparişin tamamı iade edilince toplam geri
    --    alınan = ödenen mal bedeli − komisyon olur.
    v_debit := GREATEST(v_request.refund_amount - v_comm, 0);

    IF v_debit > 0 AND v_shop.id IS NOT NULL THEN
      IF v_order.commission_status = 'cash_collected' THEN
        UPDATE public.shops
           SET commission_debt      = COALESCE(commission_debt, 0) + v_debit,
               cash_payment_revenue = GREATEST(COALESCE(cash_payment_revenue, 0) - v_debit, 0),
               updated_at           = now()
         WHERE id = v_shop.id;
      ELSE
        v_from := LEAST(GREATEST(v_shop.admin_credit, 0), v_debit);
        UPDATE public.shops
           SET admin_credit    = COALESCE(admin_credit, 0) - v_from,
               commission_debt = COALESCE(commission_debt, 0) + (v_debit - v_from),
               cash_payment_revenue = CASE
                 WHEN v_order.payment_method IN ('cash', 'card_on_delivery', 'cardOnDelivery')
                 THEN GREATEST(COALESCE(cash_payment_revenue, 0) - v_debit, 0)
                 ELSE cash_payment_revenue END,
               online_payment_revenue = CASE
                 WHEN v_order.payment_method IN ('cash', 'card_on_delivery', 'cardOnDelivery')
                 THEN online_payment_revenue
                 ELSE GREATEST(COALESCE(online_payment_revenue, 0) - v_debit, 0) END,
               updated_at = now()
         WHERE id = v_shop.id;
      END IF;
    END IF;
  END IF;

  -- 3) Siparişin tamamı iade edildiyse ödeme 'refunded', bekleyen kazanç iptal
  IF v_final THEN
    UPDATE public.orders
       SET payment_status = 'refunded', updated_at = now()
     WHERE id = v_order.id;

    UPDATE public.seller_earnings
       SET status = 'cancelled'
     WHERE order_id = v_order.id
       AND status IN ('pending', 'available');
  END IF;

  UPDATE public.return_requests
     SET status                   = 'approved',
         reviewed_by              = v_admin,
         reviewed_at              = now(),
         admin_response           = v_note,
         balance_transaction_id   = v_tx_id,
         seller_debit_amount      = v_debit,
         commission_refund_amount = v_comm,
         updated_at               = now()
   WHERE id = v_request.id
  RETURNING * INTO v_request;

  SELECT count(*) INTO v_item_count FROM public.return_request_items WHERE request_id = v_request.id;

  -- 4) Bildirimler
  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  VALUES (
    v_request.user_id,
    'return_approved',
    'İade Talebiniz Onaylandı',
    'Sipariş #' || v_label || ' iadeniz onaylandı.' ||
      CASE
        WHEN v_seller_cash AND v_request.refund_amount > 0
          THEN ' Ürünleri teslim ederken ₺' || to_char(v_request.refund_amount, 'FM999999990.00') ||
               ' iade tutarını satıcıdan nakit alacaksınız.'
        WHEN v_request.refund_amount > 0
          THEN ' ₺' || to_char(v_request.refund_amount, 'FM999999990.00') ||
               ' bakiyenize eklendi. Ürünleri satıcıya teslim etmeyi unutmayın.'
        ELSE ' Ürünleri satıcıya teslim etmeyi unutmayın.'
      END,
    v_request.id::text,
    'return_request',
    jsonb_build_object('request_id', v_request.id, 'order_id', v_order.id,
                       'refund_amount', v_request.refund_amount,
                       'refund_method', v_request.refund_method,
                       'balance_transaction_id', v_tx_id)
  );

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  SELECT s.owner_id,
         'return_approved_seller',
         'Onaylanan İade',
         'Sipariş #' || v_label || ' için ' ||
           CASE WHEN v_request.return_scope = 'full' THEN 'tüm ürünlerin' ELSE v_item_count || ' ürünün' END ||
           ' iadesi yönetici tarafından onaylandı.' ||
           CASE
             WHEN v_seller_cash
               THEN ' Ürünleri teslim alırken müşteriye ₺' ||
                    to_char(v_request.refund_amount, 'FM999999990.00') || ' nakit iade edin.' ||
                    CASE WHEN v_comm > 0
                         THEN ' Bu tutarın ₺' || to_char(v_comm, 'FM999999990.00') ||
                              ' komisyonu borcunuzdan düşüldü.'
                         ELSE '' END
             WHEN v_debit > 0
               THEN ' ₺' || to_char(v_debit, 'FM999999990.00') || ' hesabınızdan düşüldü.' ||
                    ' Ürünleri teslim alınca İade Talepleri ekranından onaylayın.'
             ELSE ' Ürünleri teslim alınca İade Talepleri ekranından onaylayın.'
           END,
         v_request.id::text,
         'return_request',
         jsonb_build_object('request_id', v_request.id, 'order_id', v_order.id,
                            'refund_method', v_request.refund_method,
                            'seller_debit_amount', v_debit,
                            'commission_refund_amount', v_comm)
    FROM public.shops s
   WHERE s.id = v_order.shop_id
     AND s.owner_id IS NOT NULL;

  RETURN v_request;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
