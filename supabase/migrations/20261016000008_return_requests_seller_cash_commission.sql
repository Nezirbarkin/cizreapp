-- ============================================================================
-- İade: kuryeli satıcı + kapıda ödeme → satıcı nakit iade eder, komisyon düşer
-- (2026-10-16, 20261016000007'nin devamı)
-- ----------------------------------------------------------------------------
-- Kuryesi olan satıcı kapıda nakit/kart tahsil ettiğinde (orders.commission_status
-- = 'cash_collected') para satıcıdadır; satıcı admine yalnız komisyon kadar
-- borçlanır (shops.commission_debt). Böyle bir siparişte iade onaylanınca:
--   * Platform müşteriye bakiye iadesi YAPMAZ; müşteriye nakdi satıcı iade eder
--     (refund_method = 'seller_cash').
--   * İade edilen tutarın komisyonu satıcının komisyon borcundan düşülür
--     (borç yetmezse kalan admin_credit olur). Örnek: 100 ₺, %10, borç 10 ₺;
--     60 ₺ iade → borç 4 ₺; tümü iade → borç 0 ₺.
--   * total_collected_cash iade tutarı, cash_payment_revenue satıcı neti kadar azalır.
-- Diğer siparişlerde (bakiye/online/kuryesiz kapıda) akış aynıdır: iade müşteri
-- bakiyesine, satıcıdan yalnız net payı düşülür (komisyon yine admine kalmaz).
-- commission_refund_amount: her talepte adminin vazgeçtiği komisyon.
-- ============================================================================

BEGIN;

-- ── 1) Sütunlar ────────────────────────────────────────────────────────────
ALTER TABLE public.return_requests
  ADD COLUMN IF NOT EXISTS refund_method            text NOT NULL DEFAULT 'balance',
  ADD COLUMN IF NOT EXISTS commission_refund_amount numeric(12,2) NOT NULL DEFAULT 0;

ALTER TABLE public.return_requests
  DROP CONSTRAINT IF EXISTS return_requests_refund_method_check;
ALTER TABLE public.return_requests
  ADD CONSTRAINT return_requests_refund_method_check
  CHECK (refund_method IN ('balance', 'seller_cash'));

COMMENT ON COLUMN public.return_requests.refund_method IS
  'balance = platform müşteri bakiyesine iade eder; seller_cash = kuryeli satıcı nakdi kendisi iade eder.';
COMMENT ON COLUMN public.return_requests.commission_refund_amount IS
  'İade edilen tutar için adminin vazgeçtiği komisyon.';

-- Bekleyen talepler sipariş durumuna göre işaretlenir.
UPDATE public.return_requests r
   SET refund_method = 'seller_cash'
  FROM public.orders o
 WHERE o.id = r.order_id
   AND r.status = 'pending'
   AND o.commission_status = 'cash_collected';

-- ── 2) Talep açma: iade yöntemi talep anında kilitlenir ────────────────────
CREATE OR REPLACE FUNCTION public.create_return_request(
  p_order_id uuid,
  p_reason   text,
  p_items    jsonb DEFAULT NULL
) RETURNS public.return_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  c_window_days CONSTANT integer := 14;
  v_uid          uuid := auth.uid();
  v_reason       text := btrim(COALESCE(p_reason, ''));
  v_order        record;
  v_items_sum    numeric;
  v_goods_paid   numeric;
  v_ratio        numeric;
  v_prev_refund  numeric;
  v_value        numeric := 0;
  v_refund       numeric;
  v_all_order    boolean;
  v_final        boolean;
  v_scope        text;
  v_line_count   integer;
  v_request      public.return_requests;
  v_label        text;
  v_bad          text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  IF length(v_reason) < 3 THEN
    RAISE EXCEPTION 'İade sebebi en az 3 karakter olmalı' USING ERRCODE = '22023';
  END IF;
  IF length(v_reason) > 1000 THEN
    RAISE EXCEPTION 'İade sebebi en fazla 1000 karakter olabilir' USING ERRCODE = '22023';
  END IF;

  SELECT id, user_id, shop_id, status::text AS status, total, delivery_fee,
         payment_method::text AS payment_method, payment_status::text AS payment_status,
         order_number, delivered_at, updated_at, created_at,
         commission_status::text AS commission_status
    INTO v_order
    FROM public.orders
   WHERE id = p_order_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sipariş bulunamadı' USING ERRCODE = 'P0002';
  END IF;

  IF v_order.user_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Bu siparişe erişim yetkiniz yok' USING ERRCODE = '42501';
  END IF;

  IF v_order.status <> 'delivered' THEN
    RAISE EXCEPTION 'Yalnızca teslim edilmiş siparişler iade edilebilir' USING ERRCODE = 'P0001';
  END IF;

  IF v_order.payment_status = 'refunded' THEN
    RAISE EXCEPTION 'Bu siparişin ödemesi zaten iade edilmiş' USING ERRCODE = 'P0001';
  END IF;

  IF COALESCE(v_order.delivered_at, v_order.updated_at, v_order.created_at)
       < now() - make_interval(days => c_window_days) THEN
    RAISE EXCEPTION 'İade süresi doldu (teslimattan sonra % gün)', c_window_days
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (SELECT 1 FROM public.return_requests
              WHERE order_id = p_order_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Bu sipariş için bekleyen bir iade talebiniz zaten var' USING ERRCODE = 'P0001';
  END IF;

  IF p_items IS NOT NULL AND jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Geçersiz ürün listesi' USING ERRCODE = '22023';
  END IF;

  -- Sipariş kalemleri + kalan iade edilebilir adet
  CREATE TEMP TABLE IF NOT EXISTS pg_temp.rr_lines (
    order_item_id uuid PRIMARY KEY,
    product_id    uuid,
    product_name  text,
    image_url     text,
    ordered_qty   integer,
    line_subtotal numeric,
    remaining_qty integer,
    req_qty       integer
  ) ON COMMIT DROP;
  TRUNCATE pg_temp.rr_lines;

  INSERT INTO pg_temp.rr_lines
  SELECT oi.id, oi.product_id, COALESCE(oi.product_name, 'Ürün'), oi.product_image_url,
         oi.quantity,
         COALESCE(oi.subtotal, COALESCE(oi.price, oi.product_price, 0) * oi.quantity),
         GREATEST(oi.quantity - public.return_reserved_quantity(oi.id), 0),
         0
    FROM public.order_items oi
   WHERE oi.order_id = p_order_id
     AND oi.quantity > 0;

  SELECT COALESCE(sum(line_subtotal), 0) INTO v_items_sum FROM pg_temp.rr_lines;
  IF v_items_sum <= 0 THEN
    RAISE EXCEPTION 'Bu siparişte iade edilebilir ürün yok' USING ERRCODE = 'P0001';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    UPDATE pg_temp.rr_lines SET req_qty = remaining_qty;
  ELSE
    -- Sipariş dışı / bozuk kalem
    SELECT e ->> 'order_item_id' INTO v_bad
      FROM jsonb_array_elements(p_items) e
     WHERE jsonb_typeof(e) <> 'object'
        OR NOT EXISTS (SELECT 1 FROM pg_temp.rr_lines l
                        WHERE l.order_item_id::text = lower(COALESCE(e ->> 'order_item_id', '')))
     LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'Ürün bu siparişe ait değil' USING ERRCODE = '22023';
    END IF;

    -- (Kısa devre garanti olmadığından tür dönüşümü CASE içinde.)
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) e
                WHERE CASE WHEN COALESCE(e ->> 'quantity', '') ~ '^[0-9]{1,6}$'
                           THEN (e ->> 'quantity')::integer < 1
                           ELSE true END) THEN
      RAISE EXCEPTION 'İade adedi en az 1 olmalı' USING ERRCODE = '22023';
    END IF;

    UPDATE pg_temp.rr_lines l
       SET req_qty = x.qty
      FROM (SELECT (e ->> 'order_item_id')::uuid AS id,
                   sum((e ->> 'quantity')::integer)::integer AS qty
              FROM jsonb_array_elements(p_items) e
             GROUP BY 1) x
     WHERE l.order_item_id = x.id;

    SELECT product_name INTO v_bad
      FROM pg_temp.rr_lines WHERE req_qty > remaining_qty LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION '"%" için iade adedi kalan adetten fazla', v_bad USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT count(*) INTO v_line_count FROM pg_temp.rr_lines WHERE req_qty > 0;
  IF v_line_count = 0 THEN
    RAISE EXCEPTION 'Bu siparişte iade edilebilecek ürün kalmadı' USING ERRCODE = 'P0001';
  END IF;

  -- Tutarlar
  v_goods_paid := GREATEST(COALESCE(v_order.total, 0) - COALESCE(v_order.delivery_fee, 0), 0);
  v_ratio      := LEAST(v_goods_paid / v_items_sum, 1);

  SELECT COALESCE(sum(refund_amount), 0) INTO v_prev_refund
    FROM public.return_requests
   WHERE order_id = p_order_id AND status IN ('approved', 'completed');

  SELECT COALESCE(sum(line_subtotal / ordered_qty * req_qty), 0) INTO v_value
    FROM pg_temp.rr_lines WHERE req_qty > 0;

  v_final     := NOT EXISTS (SELECT 1 FROM pg_temp.rr_lines WHERE req_qty < remaining_qty);
  v_all_order := v_final AND NOT EXISTS (SELECT 1 FROM pg_temp.rr_lines WHERE remaining_qty < ordered_qty);
  v_scope     := CASE WHEN v_all_order THEN 'full' ELSE 'partial' END;

  IF v_final THEN
    v_refund := GREATEST(v_goods_paid - v_prev_refund, 0);
  ELSE
    v_refund := LEAST(round(v_value * v_ratio, 2), GREATEST(v_goods_paid - v_prev_refund, 0));
  END IF;

  INSERT INTO public.return_requests (
    order_id, user_id, shop_id, reason, status, return_scope,
    payment_method, refund_method, refund_amount, created_at
  ) VALUES (
    p_order_id, v_uid, v_order.shop_id, v_reason, 'pending', v_scope,
    v_order.payment_method,
    CASE WHEN v_order.commission_status = 'cash_collected' THEN 'seller_cash' ELSE 'balance' END,
    v_refund, now()
  )
  RETURNING * INTO v_request;

  INSERT INTO public.return_request_items (
    request_id, order_item_id, product_id, product_name, product_image_url,
    quantity, unit_price, line_total
  )
  SELECT v_request.id, order_item_id, product_id, product_name, image_url,
         req_qty,
         round(line_subtotal / ordered_qty, 2),
         round(line_subtotal / ordered_qty * req_qty, 2)
    FROM pg_temp.rr_lines
   WHERE req_qty > 0;

  v_label := COALESCE(v_order.order_number::text, substring(p_order_id::text, 1, 8));

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  SELECT p.id,
         'return_request',
         'Yeni İade Talebi',
         'Sipariş #' || v_label || ' için ' ||
           CASE WHEN v_scope = 'full' THEN 'tüm ürünlerin' ELSE v_line_count || ' ürünün' END ||
           ' iadesi istendi (₺' || to_char(v_refund, 'FM999999990.00') || '). Sebep: ' || v_reason,
         v_request.id::text,
         'return_request',
         jsonb_build_object('request_id', v_request.id, 'order_id', p_order_id,
                            'refund_amount', v_refund, 'return_scope', v_scope)
    FROM public.profiles p
   WHERE p.role = 'admin';

  RETURN v_request;
END;
$$;

-- ── 3) Yönetici onayı: iade yöntemine göre para hareketi ───────────────────
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
         total, delivery_fee, admin_commission, seller_net_amount, order_number
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

    -- 2) Satıcı payını (iade − komisyon) mağaza hesabından düş
    IF COALESCE(v_order.total, 0) > 0 AND v_request.refund_amount > 0 THEN
      v_share := LEAST(GREATEST(COALESCE(v_order.seller_net_amount, v_order.total) / v_order.total, 0), 1);
      IF v_final THEN
        SELECT COALESCE(sum(seller_debit_amount), 0) INTO v_prev
          FROM public.return_requests
         WHERE order_id = v_order.id AND status IN ('approved', 'completed');
        v_debit := GREATEST(COALESCE(v_order.seller_net_amount, v_order.total) - v_prev, 0);
        v_debit := LEAST(v_debit, v_request.refund_amount);
      ELSE
        v_debit := round(v_request.refund_amount * v_share, 2);
      END IF;
    END IF;

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
