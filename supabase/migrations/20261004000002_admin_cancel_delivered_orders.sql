-- ============================================================================
-- Admin: TESLİM EDİLMİŞ siparişi de iptal edebilsin
-- ----------------------------------------------------------------------------
-- Önceki sürüm (20260709000004) yalnızca pending/confirmed/preparing/ready/
-- on_the_way aşamalarını iptal ediyordu; 'delivered' için
-- "admin tarafından iptal edilemez" hatası veriyordu.
--
-- Teslimden sonra iptalde ek olarak şunlar ele alınır:
--   * Satıcı bakiyesi: update_shop_balance tetikleyicisi delivered->cancelled
--     geçişinde zaten geri alıyor (admin_credit / *_payment_revenue /
--     commission_debt). Burada dokunulmaz.
--   * seller_earnings: henüz çekilmemiş (pending/available) kayıt 'cancelled'
--     olur. Çekilmiş (withdrawn) kayıt geri alınamaz, olduğu gibi kalır.
--   * invoices: yalnızca 'draft' fatura iptal edilir. Kuyruğa girmiş/gönderilmiş
--     fatura için sağlayıcıda ayrı iptal/iade faturası gerekir, dokunulmaz.
--   * Satıcıya bildirim gider (bakiyesi azaldığı için sessiz kalmamalı).
--   * Stok geri yüklenmez: ürün müşteriye teslim edilmişti (restore_product_stock
--     zaten yalnız confirmed->cancelled'da çalışır). Kurye kazancı da korunur;
--     teslimatı kurye yapmıştı.
--
-- Çifte iade koruması: payment_status zaten 'refunded' ise bakiyeye tekrar
-- iade yapılmaz (yalnız iptal edilir).
--
-- CREATE OR REPLACE: imza ve dönüş tipi aynı, mevcut EXECUTE yetkileri korunur.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_cancel_with_refund(
    p_order_id UUID,
    p_reason   TEXT DEFAULT 'Admin tarafından iptal edildi'
) RETURNS public.cancellation_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_id              UUID := auth.uid();
    v_order                 RECORD;
    v_request               public.cancellation_requests;
    v_refund_method         TEXT;
    v_refund_amount         NUMERIC(12,2);
    v_transaction_id        UUID;
    v_order_label           TEXT;
    v_shop_owner_id         UUID;
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
    END IF;

    -- Sipariş kontrolü (FOR UPDATE ile yarış koşulu önleme)
    SELECT id, user_id, shop_id, status, total, payment_method, payment_status,
           cancelled_at, order_number
      INTO v_order
      FROM public.orders
     WHERE id = p_order_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sipariş bulunamadı' USING ERRCODE = 'P0002';
    END IF;

    -- Zaten iptal edilmişse idempotent davran
    IF v_order.status = 'cancelled' THEN
        SELECT * INTO v_request
          FROM public.cancellation_requests
         WHERE order_id = p_order_id
         ORDER BY created_at DESC
         LIMIT 1;
        IF FOUND THEN
            RETURN v_request;
        END IF;
        RAISE EXCEPTION 'Sipariş zaten iptal edilmiş' USING ERRCODE = 'P0001';
    END IF;

    -- İptal edilebilir aşamalar (teslim edilmiş sipariş dahil)
    IF v_order.status NOT IN ('pending','confirmed','preparing','ready','on_the_way','delivered') THEN
        RAISE EXCEPTION 'Bu aşamadaki sipariş (status: %) admin tarafından iptal edilemez', v_order.status
            USING ERRCODE = 'P0001';
    END IF;

    -- İade snapshot'ı (payment_method'a göre; zaten iade edilmişse tekrar yok)
    IF v_order.payment_method IN ('balance','online')
       AND v_order.payment_status IS DISTINCT FROM 'refunded' THEN
        v_refund_method := 'balance';
        v_refund_amount := COALESCE(v_order.total, 0);
    ELSE
        v_refund_method := 'none';
        v_refund_amount := 0;
    END IF;

    -- 1) cancellation_requests kaydı (audit trail için)
    INSERT INTO public.cancellation_requests (
        order_id, user_id, shop_id, reason,
        order_total, payment_method, refund_method, refund_amount,
        status, reviewed_by, reviewed_at
    ) VALUES (
        p_order_id, v_order.user_id, v_order.shop_id, btrim(p_reason),
        COALESCE(v_order.total, 0), COALESCE(v_order.payment_method, 'cash'),
        v_refund_method, v_refund_amount,
        'approved', v_admin_id, NOW()
    )
    RETURNING * INTO v_request;

    -- 2) İade: refund_amount > 0 ise bakiyeye atomik ekle
    IF v_refund_method = 'balance' AND v_refund_amount > 0 THEN
        v_transaction_id := public.add_to_balance(
            p_user_id        := v_order.user_id,
            p_amount         := v_refund_amount,
            p_type           := 'refund'::public.balance_transaction_type,
            p_reference_type := 'cancellation_request',
            p_reference_id   := v_request.id,
            p_description    := 'Admin iptal iadesi - Sipariş #' ||
                                COALESCE(v_order.order_number::text,
                                         substring(p_order_id::text, 1, 8)),
            p_payment_method := 'balance',
            p_metadata       := jsonb_build_object(
                                    'source', 'admin_cancel_with_refund',
                                    'admin_id', v_admin_id,
                                    'original_payment_method', v_order.payment_method,
                                    'was_delivered', v_order.status = 'delivered'
                               )
        );

        UPDATE public.cancellation_requests
           SET balance_transaction_id = v_transaction_id
         WHERE id = v_request.id
        RETURNING * INTO v_request;
    END IF;

    -- 3) Siparişi iptal et. Teslimden iptalde update_shop_balance tetikleyicisi
    --    satıcı bakiyesini geri alır; confirmed->cancelled'da stok geri yüklenir.
    UPDATE public.orders
       SET status              = 'cancelled',
           payment_status      = CASE WHEN v_refund_amount > 0 THEN 'refunded'
                                      ELSE payment_status END,
           cancelled_at        = NOW(),
           cancellation_reason = btrim(p_reason),
           updated_at          = NOW()
     WHERE id = p_order_id;

    v_order_label := COALESCE(v_order.order_number::text,
                              substring(p_order_id::text, 1, 8));

    -- 4) Teslim edilmiş siparişin yan kayıtları + satıcıya bildirim
    IF v_order.status = 'delivered' THEN
        UPDATE public.seller_earnings
           SET status = 'cancelled'
         WHERE order_id = p_order_id
           AND status IN ('pending', 'available');

        UPDATE public.invoices
           SET status = 'cancelled', updated_at = NOW()
         WHERE order_id = p_order_id
           AND status = 'draft';

        SELECT owner_id INTO v_shop_owner_id
          FROM public.shops
         WHERE id = v_order.shop_id;

        IF v_shop_owner_id IS NOT NULL THEN
            INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
            VALUES (
                v_shop_owner_id,
                'order_cancelled_by_admin',
                'Teslim Edilen Sipariş İptal Edildi',
                'Sipariş #' || v_order_label || ' yönetici tarafından iptal edildi. ' ||
                'Bu siparişin geliri bakiyenizden düşüldü.',
                p_order_id::text,
                'order',
                jsonb_build_object(
                    'order_id', p_order_id,
                    'request_id', v_request.id,
                    'cancelled_by_admin', v_admin_id,
                    'was_delivered', true
                )
            );
        END IF;
    END IF;

    -- 5) Müşteriye bildirim
    INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
    VALUES (
        v_order.user_id,
        'cancellation_approved',
        CASE WHEN v_refund_amount > 0 THEN 'İptal Edildi - İade Yapıldı'
             ELSE 'Siparişiniz İptal Edildi' END,
        CASE WHEN v_refund_amount > 0
             THEN 'Sipariş #' || v_order_label || ' admin tarafından iptal edildi. ₺' ||
                  to_char(v_refund_amount, 'FM999999990.00') ||
                  ' bakiyenize eklendi.'
             ELSE 'Sipariş #' || v_order_label || ' admin tarafından iptal edildi.' END,
        p_order_id::text,
        'cancellation_request',
        jsonb_build_object(
            'request_id', v_request.id,
            'order_id', p_order_id,
            'refund_amount', v_refund_amount,
            'balance_transaction_id', v_transaction_id,
            'cancelled_by_admin', v_admin_id
        )
    );

    RETURN v_request;
END;
$$;

COMMENT ON FUNCTION public.admin_cancel_with_refund(UUID, TEXT) IS
'Admin tek-adım sipariş iptali (teslim edilmiş dahil): sipariş cancelled + (iade varsa) bakiyeye eklendi + müşteriye bildirim. Teslimden iptalde satıcı bakiyesi update_shop_balance ile geri alınır, bekleyen seller_earnings/taslak fatura iptal edilir, satıcıya bildirim gider. Atomik.';
