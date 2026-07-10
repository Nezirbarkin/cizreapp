-- ============================================================================
-- İPTAL + İADE ADMIN ONAYLI AKIŞI — Admin Tek-Adım İptal RPC
-- ----------------------------------------------------------------------------
-- Bu migration, admin tarafından sipariş iptal edildiğinde de iade bakiyeye
-- yansımasını sağlar. Admin "İptal Edildi" durumunu seçtiğinde onay diyaloğu
-- çıkacak; admin onaylayınca TEK ADIMDA hem sipariş iptal hem bakiye iade
-- gerçekleşir (müşteri talebi + admin onayı ayrı adımlarına gerek yok).
--
-- Mantık: approve_cancellation_request ile aynı (atomik), farkı:
--   - cancellation_request kaydı yine oluşturulur (audit trail),
--     ama admin adına (user_id = NULL çünkü müşteri talep etmedi,
--     sadece admin kararı; veya müşteri talep ediyse user_id=sipariş sahibi)
--   - status direkt 'approved' set edilir, reviewed_by = auth.uid(),
--     reviewed_at = NOW()
--   - approve'daki FOR UPDATE kilidi + status='pending' kontrolü
--     bu RPC'de yok (tek adım, yarış koşulu yok)
--
-- İade kuralları (create_cancellation_request ile aynı snapshot):
--   payment_method IN ('balance','online') -> add_to_balance (iade var)
--   payment_method IN ('cash','card_on_delivery') -> sadece iptal (iade yok)
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_cancel_with_refund(UUID, TEXT);

CREATE FUNCTION public.admin_cancel_with_refund(
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
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
    END IF;

    -- Sipariş kontrolü (FOR UPDATE ile yarış koşulu önleme)
    SELECT id, user_id, shop_id, status, total, payment_method,
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
        -- Eğer önceden approved bir talep varsa onu döndür, yoksa yine de bir
        -- kayıt oluşturmayı reddet (zaten iptal edilmiş)
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

    -- Sadece iptal edilebilir aşamalardaki siparişler
    IF v_order.status NOT IN ('pending','confirmed','preparing','ready','on_the_way') THEN
        RAISE EXCEPTION 'Bu aşamadaki sipariş (status: %) admin tarafından iptal edilemez', v_order.status
            USING ERRCODE = 'P0001';
    END IF;

    -- İade snapshot'ı (payment_method'a göre)
    IF v_order.payment_method IN ('balance','online') THEN
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
                                    'original_payment_method', v_order.payment_method
                               )
        );

        UPDATE public.cancellation_requests
           SET balance_transaction_id = v_transaction_id
         WHERE id = v_request.id
        RETURNING * INTO v_request;
    END IF;

    -- 3) Siparişi iptal et (restore_product_stock trigger confirmed->cancelled'da çalışır)
    UPDATE public.orders
       SET status              = 'cancelled',
           payment_status      = CASE WHEN v_refund_amount > 0 THEN 'refunded'
                                      ELSE payment_status END,
           cancelled_at        = NOW(),
           cancellation_reason = btrim(p_reason),
           updated_at          = NOW()
     WHERE id = p_order_id;

    -- 4) Müşteriye bildirim
    v_order_label := COALESCE(v_order.order_number::text,
                              substring(p_order_id::text, 1, 8));

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
'Admin tek-adım sipariş iptali: sipariş cancelled + (iade varsa) bakiyeye eklendi + müşteriye bildirim. Müşteri talebi gerekmez. Atomik.';

GRANT EXECUTE ON FUNCTION public.admin_cancel_with_refund(UUID, TEXT)
    TO authenticated;