-- ============================================================================
-- İPTAL + İADE ADMIN ONAYLI AKIŞI — RPC fonksiyonları
-- ----------------------------------------------------------------------------
-- 1) create_cancellation_request(p_order_id, p_reason)  -> müşteri çağırır
-- 2) approve_cancellation_request(p_request_id, p_admin_response) -> admin
-- 3) reject_cancellation_request(p_request_id, p_admin_response) -> admin
--
-- Tüm RPC'ler SECURITY DEFINER + search_path=public (linter güvenliği).
-- add_to_balance RETURNS UUID (transaction_id) — plan buna göre düzenlendi.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0) Notification tiplerini genişlet (cancellation_request/approved/rejected)
-- ---------------------------------------------------------------------------
-- Mevcut constraint'i kaldır (bu sefer çalışacak; önceki denemede hata
-- alınca constraint silinmemişti, aşağıdaki tipler eksik olduğu için).
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Yeni constraint: önceki tüm tipler + eksik kalan (pending_review, story_like)
-- + yeni iptal talebi tipleri. Mevcut tüm satırlar bu kurala uyduğu için
-- sıradan ADD CONSTRAINT (NOT VALID gerekmez) sorunsuz çalışır.
-- Not: "IF NOT EXISTS" kullanılmıyor — eski PostgreSQL sürümlerinde constraint
-- için desteklenmiyor. Yukarıdaki DROP CONSTRAINT IF EXISTS zaten idempotent.
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
CHECK (type IN (
  -- Sosyal
  'like','post_like','comment','post_comment','comment_mention','mention',
  'follow','new_follower','follow_request','group_join_request','group_member_joined',
  'story_like',
  -- Sipariş
  'order','order_update','order_confirmed','order_ready','order_delivered',
  'order_status','new_order','delivery',
  -- Mağaza
  'shop','shop_review','shop_review_reply','review_request','review_pending',
  -- Destek
  'support_response','support_status','complaint_response','report',
  -- Mesaj
  'message','chat',
  -- Admin
  'admin_notification',
  -- Ödeme
  'payout_approved','payout_rejected',
  -- Doğrulama
  'verification_code',
  -- Kurye
  'courier_order_assigned','courier_new_order','courier_order_ready',
  -- İçerik denetimi
  'pending_review',
  -- İptal talebi (yeni)
  'cancellation_request','cancellation_approved','cancellation_rejected'
));

-- ---------------------------------------------------------------------------
-- 1) create_cancellation_request
--    Müşteri iptal talebi açar. Sipariş sahibi + status uygun + aktif talep yok.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_cancellation_request(UUID, TEXT);

CREATE FUNCTION public.create_cancellation_request(
    p_order_id UUID,
    p_reason   TEXT
) RETURNS public.cancellation_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id       UUID := auth.uid();
    v_order         RECORD;
    v_refund_method TEXT;
    v_refund_amount NUMERIC(12,2);
    v_existing      INT;
    v_result        public.cancellation_requests;
    v_order_label   TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN
        RAISE EXCEPTION 'İptal sebebi en az 3 karakter olmalı' USING ERRCODE = '22023';
    END IF;

    -- Sipariş bilgileri
    SELECT id, user_id, shop_id, status, total, payment_method, order_number
      INTO v_order
      FROM public.orders
     WHERE id = p_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sipariş bulunamadı' USING ERRCODE = 'P0002';
    END IF;

    IF v_order.user_id IS DISTINCT FROM v_user_id THEN
        RAISE EXCEPTION 'Bu siparişe erişim yetkiniz yok' USING ERRCODE = '42501';
    END IF;

    -- Sadece henüz teslim edilmemiş siparişler iptal talebine gelir
    IF v_order.status NOT IN ('pending','confirmed','preparing','ready','on_the_way') THEN
        RAISE EXCEPTION 'Bu aşamadaki sipariş (status: %) için iptal talebi açılamaz', v_order.status
            USING ERRCODE = 'P0001';
    END IF;

    -- Aktif (pending) talep var mı?
    SELECT count(*) INTO v_existing
      FROM public.cancellation_requests
     WHERE order_id = p_order_id
       AND status = 'pending';

    IF v_existing > 0 THEN
        RAISE EXCEPTION 'Bu sipariş için bekleyen iptal talebi zaten var' USING ERRCODE = 'P0001';
    END IF;

    -- İADE SNAPSHOT
    IF v_order.payment_method IN ('balance','online') THEN
        v_refund_method := 'balance';
        v_refund_amount := COALESCE(v_order.total, 0);
    ELSE
        v_refund_method := 'none';
        v_refund_amount := 0;
    END IF;

    -- Talep kaydı
    INSERT INTO public.cancellation_requests (
        order_id, user_id, shop_id, reason,
        order_total, payment_method, refund_method, refund_amount
    ) VALUES (
        p_order_id, v_user_id, v_order.shop_id, btrim(p_reason),
        COALESCE(v_order.total, 0), COALESCE(v_order.payment_method, 'cash'),
        v_refund_method, v_refund_amount
    )
    RETURNING * INTO v_result;

    -- Admin(ler)e bildirim: yeni iptal talebi
    v_order_label := COALESCE(v_order.order_number::text, substring(p_order_id::text, 1, 8));

    INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
    SELECT
        p.id,
        'cancellation_request',
        'Yeni İptal Talebi',
        'Sipariş #' || v_order_label || ' için iptal talebi açıldı. Sebep: ' || btrim(p_reason),
        p_order_id::text,
        'cancellation_request',
        jsonb_build_object('request_id', v_result.id, 'order_id', p_order_id, 'refund_amount', v_refund_amount)
    FROM public.profiles p
    WHERE p.role = 'admin';

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.create_cancellation_request(UUID, TEXT) IS
'Müşteri iptal talebi açar. status pending/confirmed/preparing/ready/on_the_way olmalı. Aktif talep yoksa kabul eder, iade snapshotını kilitler.';

GRANT EXECUTE ON FUNCTION public.create_cancellation_request(UUID, TEXT)
    TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) approve_cancellation_request
--    Admin onaylar -> sipariş cancelled + (iade varsa) add_to_balance + bildirim
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.approve_cancellation_request(UUID, TEXT);

CREATE FUNCTION public.approve_cancellation_request(
    p_request_id     UUID,
    p_admin_response TEXT DEFAULT NULL
) RETURNS public.cancellation_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_id              UUID := auth.uid();
    v_request               public.cancellation_requests;
    v_transaction_id        UUID;
    v_order_label           TEXT;
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
    END IF;

    -- Talebi kilitle (race condition: iki admin aynı anda onaylamaya çalışırsa)
    SELECT * INTO v_request
      FROM public.cancellation_requests
     WHERE id = p_request_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'İptal talebi bulunamadı' USING ERRCODE = 'P0002';
    END IF;

    IF v_request.status IS DISTINCT FROM 'pending' THEN
        RAISE EXCEPTION 'Bu talep zaten % durumunda, tekrar işlenemez', v_request.status
            USING ERRCODE = 'P0001';
    END IF;

    -- 2a) İADE: refund_method='balance' ve refund_amount>0 ise bakiyeye atomik ekle
    IF v_request.refund_method = 'balance' AND v_request.refund_amount > 0 THEN
        v_transaction_id := public.add_to_balance(
            p_user_id        := v_request.user_id,
            p_amount         := v_request.refund_amount,
            p_type           := 'refund'::public.balance_transaction_type,
            p_reference_type := 'cancellation_request',
            p_reference_id   := v_request.id,
            p_description    := 'İptal iadesi - Sipariş #' ||
                                COALESCE((SELECT order_number::text FROM public.orders WHERE id = v_request.order_id),
                                         substring(v_request.order_id::text, 1, 8)),
            p_payment_method := 'balance',
            p_metadata       := jsonb_build_object(
                                    'source', 'cancellation_request',
                                    'approved_by', v_admin_id,
                                    'original_payment_method', v_request.payment_method
                               )
        );
    END IF;

    -- 2b) Siparişi iptal et
    --     payment_status: iade yapıldıysa 'refunded', yapılmadıysa (cash/card) kalır
    --     Not: orders.payment_status enum('pending','paid','refunded').
    UPDATE public.orders
       SET status              = 'cancelled',
           payment_status      = CASE WHEN v_request.refund_amount > 0 THEN 'refunded'
                                      ELSE payment_status END,
           cancelled_at        = NOW(),
           cancellation_reason = v_request.reason,
           updated_at          = NOW()
     WHERE id = v_request.order_id;
    -- restore_product_stock trigger'ı confirmed->cancelled geçişinde stokları geri yükler

    -- 2c) Talebi approved yap + transaction referansını sakla
    UPDATE public.cancellation_requests
       SET status                   = 'approved',
           reviewed_by              = v_admin_id,
           reviewed_at              = NOW(),
           admin_response           = p_admin_response,
           balance_transaction_id   = v_transaction_id,
           updated_at               = NOW()
     WHERE id = p_request_id
    RETURNING * INTO v_request;

    -- 2d) Müşteriye bildirim
    v_order_label := COALESCE(
        (SELECT order_number::text FROM public.orders WHERE id = v_request.order_id),
        substring(v_request.order_id::text, 1, 8)
    );

    INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
    VALUES (
        v_request.user_id,
        'cancellation_approved',
        CASE WHEN v_request.refund_amount > 0 THEN 'İptal Onaylandı - İade Yapıldı'
             ELSE 'Sipariş İptal Edildi' END,
        CASE WHEN v_request.refund_amount > 0
             THEN 'Sipariş #' || v_order_label || ' iptal edildi. ₺' ||
                  to_char(v_request.refund_amount, 'FM999999990.00') ||
                  ' bakiyenize eklendi.'
             ELSE 'Sipariş #' || v_order_label || ' iptal edildi.' END,
        v_request.order_id::text,
        'cancellation_request',
        jsonb_build_object(
            'request_id', v_request.id,
            'order_id', v_request.order_id,
            'refund_amount', v_request.refund_amount,
            'balance_transaction_id', v_transaction_id
        )
    );

    RETURN v_request;
END;
$$;

COMMENT ON FUNCTION public.approve_cancellation_request(UUID, TEXT) IS
'Admin iptal talebini onaylar. Atomik: orders cancelled + (iade varsa) add_to_balance + notification. Stok restore trigger otomatik.';

GRANT EXECUTE ON FUNCTION public.approve_cancellation_request(UUID, TEXT)
    TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) reject_cancellation_request
--    Admin reddeder -> sadece status=rejected + müşteriye bildirim
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.reject_cancellation_request(UUID, TEXT);

CREATE FUNCTION public.reject_cancellation_request(
    p_request_id     UUID,
    p_admin_response TEXT
) RETURNS public.cancellation_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_id    UUID := auth.uid();
    v_request     public.cancellation_requests;
    v_order_label TEXT;
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
    END IF;

    IF p_admin_response IS NULL OR length(btrim(p_admin_response)) < 3 THEN
        RAISE EXCEPTION 'Red sebebi (admin açıklaması) en az 3 karakter olmalı' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_request
      FROM public.cancellation_requests
     WHERE id = p_request_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'İptal talebi bulunamadı' USING ERRCODE = 'P0002';
    END IF;

    IF v_request.status IS DISTINCT FROM 'pending' THEN
        RAISE EXCEPTION 'Bu talep zaten % durumunda, tekrar işlenemez', v_request.status
            USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.cancellation_requests
       SET status         = 'rejected',
           reviewed_by    = v_admin_id,
           reviewed_at    = NOW(),
           admin_response = btrim(p_admin_response),
           updated_at     = NOW()
     WHERE id = p_request_id
    RETURNING * INTO v_request;

    v_order_label := COALESCE(
        (SELECT order_number::text FROM public.orders WHERE id = v_request.order_id),
        substring(v_request.order_id::text, 1, 8)
    );

    INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
    VALUES (
        v_request.user_id,
        'cancellation_rejected',
        'İptal Talebi Reddedildi',
        'Sipariş #' || v_order_label || ' için iptal talebiniz reddedildi. ' ||
        COALESCE(btrim(p_admin_response), ''),
        v_request.order_id::text,
        'cancellation_request',
        jsonb_build_object('request_id', v_request.id, 'order_id', v_request.order_id)
    );

    RETURN v_request;
END;
$$;

COMMENT ON FUNCTION public.reject_cancellation_request(UUID, TEXT) IS
'Admin iptal talebini reddeder. Sipariş etkilenmez. Müşteriye bildirim gönderilir.';

GRANT EXECUTE ON FUNCTION public.reject_cancellation_request(UUID, TEXT)
    TO authenticated;