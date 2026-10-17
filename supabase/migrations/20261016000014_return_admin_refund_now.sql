-- ============================================================================
-- İade: yönetici satıcıyı beklemeden müşteriye hemen iade edebilir (2026-10-16)
-- ----------------------------------------------------------------------------
-- 20261016000013 ile para iadesi satıcının "Teslim Aldım" onayına bağlandı.
-- Kullanıcı isteği: yönetici dilerse satıcıyı beklemeden müşterinin bakiyesine
-- iadeyi hemen yapabilsin.
--
--   admin_refund_return_now(talep, not):
--     * bekleyen talebi onaylar (ya da onaylı talebi kullanır),
--     * tutarı HEMEN müşterinin bakiyesine ekler, satıcıdan (iade − iade
--       edilen tutarın komisyonu) geri alır;
--     * kuryeli satıcının kapıda tahsilatında (seller_cash) da bakiyeye iade
--       yapılır: satıcı müşteriye nakit VERMEZ, iade payı satıcının borcuna
--       yazılır (refund_method → 'balance');
--     * talep 'approved' kalır: satıcı ürünleri teslim alınca "Teslim Aldım"
--       der, bu kez para hareketi olmaz, talep 'completed' olur.
--
-- Para hareketi tek yerde: settle_return_request (iç fonksiyon). Bir talep
-- yalnız bir kez ödenir: return_requests.refunded_at.
-- ============================================================================

BEGIN;

ALTER TABLE public.return_requests
  ADD COLUMN IF NOT EXISTS refunded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refunded_by uuid;

COMMENT ON COLUMN public.return_requests.refunded_at IS
  'Para iadesinin yapıldığı an (satıcının teslim alması ya da yöneticinin hemen iadesi). Bir talep yalnız bir kez ödenir.';

-- Önceki akışlarda parası ödenmiş talepler
UPDATE public.return_requests
   SET refunded_at = COALESCE(received_at, reviewed_at, updated_at, created_at),
       refunded_by = COALESCE(received_by, reviewed_by)
 WHERE refunded_at IS NULL
   AND (balance_transaction_id IS NOT NULL
        OR seller_debit_amount > 0
        OR commission_refund_amount > 0
        OR (status = 'completed' AND refund_method = 'seller_cash'));

-- Sipariş kaleminde parası ödenmiş iade adedi
CREATE OR REPLACE FUNCTION public.return_settled_quantity(p_order_item_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(sum(i.quantity), 0)::integer
    FROM public.return_request_items i
    JOIN public.return_requests r ON r.id = i.request_id
   WHERE i.order_item_id = p_order_item_id
     AND r.refunded_at IS NOT NULL
     AND r.status IN ('approved', 'completed');
$$;
REVOKE ALL ON FUNCTION public.return_settled_quantity(uuid) FROM PUBLIC, anon, authenticated;

-- ── 1) Hesap önizlemesi: "önceki" = parası ödenmiş talepler ────────────────
CREATE OR REPLACE FUNCTION public.return_settlement_preview(p_request_id uuid)
RETURNS TABLE (commission_refund numeric, seller_debit numeric, is_final boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_request    public.return_requests;
  v_order      record;
  v_goods_paid numeric;
  v_commission numeric;
  v_prev       numeric;
  v_final      boolean;
  v_comm       numeric := 0;
BEGIN
  SELECT * INTO v_request FROM public.return_requests WHERE id = p_request_id;
  SELECT total, delivery_fee, admin_commission, seller_net_amount
    INTO v_order FROM public.orders WHERE id = v_request.order_id;

  v_goods_paid := GREATEST(COALESCE(v_order.total, 0) - COALESCE(v_order.delivery_fee, 0), 0);
  v_commission := GREATEST(COALESCE(v_order.admin_commission,
                                    COALESCE(v_order.total, 0)
                                      - COALESCE(v_order.seller_net_amount, v_order.total)), 0);

  -- Parası ödenmiş iadeler + bu talep siparişin bütün ürünlerini kapsıyor mu?
  v_final := NOT EXISTS (
    SELECT 1 FROM public.order_items oi
     WHERE oi.order_id = v_request.order_id
       AND oi.quantity > public.return_settled_quantity(oi.id)
                         + CASE WHEN v_request.refunded_at IS NOT NULL THEN 0 ELSE
                             COALESCE((SELECT sum(i.quantity) FROM public.return_request_items i
                                        WHERE i.request_id = v_request.id
                                          AND i.order_item_id = oi.id), 0) END
  );

  IF v_request.refund_amount > 0 AND v_goods_paid > 0 THEN
    SELECT COALESCE(sum(commission_refund_amount), 0) INTO v_prev
      FROM public.return_requests
     WHERE order_id = v_request.order_id
       AND refunded_at IS NOT NULL
       AND status IN ('approved', 'completed')
       AND id <> v_request.id;
    IF v_final THEN
      v_comm := GREATEST(v_commission - v_prev, 0);
    ELSE
      v_comm := LEAST(round(v_request.refund_amount * v_commission / v_goods_paid, 2),
                      GREATEST(v_commission - v_prev, 0));
    END IF;
  END IF;

  commission_refund := v_comm;
  seller_debit := CASE WHEN v_request.refund_method = 'seller_cash' THEN 0
                       ELSE GREATEST(v_request.refund_amount - v_comm, 0) END;
  is_final := v_final;
  RETURN NEXT;
END;
$$;
REVOKE ALL ON FUNCTION public.return_settlement_preview(uuid) FROM PUBLIC, anon, authenticated;

-- ── 2) Para hareketi (iç fonksiyon; yalnız DEFINER RPC'ler çağırır) ────────
CREATE OR REPLACE FUNCTION public.settle_return_request(
  p_request_id    uuid,
  p_actor         uuid,
  p_force_balance boolean DEFAULT false
) RETURNS public.return_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_request public.return_requests;
  v_order   record;
  v_preview record;
  v_shop    record;
  v_from    numeric;
  v_comm    numeric;
  v_debit   numeric;
  v_tx_id   uuid;
  v_label   text;
BEGIN
  SELECT * INTO v_request FROM public.return_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'İade talebi bulunamadı' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.refunded_at IS NOT NULL THEN
    RAISE EXCEPTION 'Bu iadenin parası zaten ödendi' USING ERRCODE = 'P0001';
  END IF;
  IF v_request.status NOT IN ('approved') THEN
    RAISE EXCEPTION 'Yalnızca onaylı iadenin parası ödenebilir (durum: %)', v_request.status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT id, shop_id, status::text AS status, payment_status::text AS payment_status,
         payment_method::text AS payment_method, commission_status::text AS commission_status,
         order_number
    INTO v_order
    FROM public.orders WHERE id = v_request.order_id FOR UPDATE;
  IF NOT FOUND OR v_order.status <> 'delivered' THEN
    RAISE EXCEPTION 'Sipariş artık teslim edilmiş durumda değil (iptal edilmiş olabilir)'
      USING ERRCODE = 'P0001';
  END IF;
  IF v_order.payment_status = 'refunded' THEN
    RAISE EXCEPTION 'Bu siparişin ödemesi zaten iade edilmiş' USING ERRCODE = 'P0001';
  END IF;

  -- Yönetici hemen iade: kapıda tahsilatta da müşteriye bakiyeden ödenir.
  IF p_force_balance AND v_request.refund_method = 'seller_cash' THEN
    UPDATE public.return_requests SET refund_method = 'balance'
     WHERE id = v_request.id
    RETURNING * INTO v_request;
  END IF;

  v_label := COALESCE(v_order.order_number::text, substring(v_order.id::text, 1, 8));
  SELECT * INTO v_preview FROM public.return_settlement_preview(v_request.id);
  v_comm  := v_preview.commission_refund;
  v_debit := v_preview.seller_debit;

  SELECT id, COALESCE(admin_credit, 0) AS admin_credit,
         COALESCE(commission_debt, 0) AS commission_debt
    INTO v_shop FROM public.shops WHERE id = v_order.shop_id FOR UPDATE;

  IF v_request.refund_method = 'seller_cash' THEN
    -- Nakdi satıcı iade etti; iade edilen tutarın komisyonu borcundan düşer.
    IF v_shop.id IS NOT NULL THEN
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
                              'refunded_by', p_actor,
                              'order_id', v_order.id,
                              'return_scope', v_request.return_scope,
                              'original_payment_method', v_order.payment_method)
      );
    END IF;

    IF v_debit > 0 AND v_shop.id IS NOT NULL THEN
      IF v_order.commission_status = 'cash_collected' THEN
        -- Nakit satıcıdaydı: müşteriye platform ödedi, satıcı payı borcuna yazılır.
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

  IF v_preview.is_final THEN
    UPDATE public.orders
       SET payment_status = 'refunded', updated_at = now()
     WHERE id = v_order.id;

    UPDATE public.seller_earnings
       SET status = 'cancelled'
     WHERE order_id = v_order.id
       AND status IN ('pending', 'available');
  END IF;

  UPDATE public.return_requests
     SET refunded_at              = now(),
         refunded_by              = p_actor,
         balance_transaction_id   = COALESCE(v_tx_id, balance_transaction_id),
         seller_debit_amount      = v_debit,
         commission_refund_amount = v_comm,
         updated_at               = now()
   WHERE id = v_request.id
  RETURNING * INTO v_request;

  PERFORM public.refresh_order_return_status(v_request.order_id);
  RETURN v_request;
END;
$$;
REVOKE ALL ON FUNCTION public.settle_return_request(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;

-- ── 3) Satıcı/yönetici teslim aldı ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_return_received(
  p_request_id uuid,
  p_restock    boolean DEFAULT false
) RETURNS public.return_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_request     public.return_requests;
  v_was_paid    boolean;
  v_label       text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request FROM public.return_requests
   WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'İade talebi bulunamadı' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_admin()
     AND NOT EXISTS (SELECT 1 FROM public.shops
                      WHERE id = v_request.shop_id AND owner_id = v_uid) THEN
    RAISE EXCEPTION 'Bu iade talebi üzerinde yetkiniz yok' USING ERRCODE = '42501';
  END IF;

  IF v_request.status <> 'approved' THEN
    RAISE EXCEPTION 'Yalnızca yönetici onaylı iadeler teslim alındı olarak işaretlenebilir (durum: %)',
      v_request.status USING ERRCODE = 'P0001';
  END IF;

  -- Yönetici hemen iade ettiyse para tekrar hareket etmez.
  v_was_paid := v_request.refunded_at IS NOT NULL;
  IF NOT v_was_paid THEN
    v_request := public.settle_return_request(v_request.id, v_uid, false);
  END IF;

  IF COALESCE(p_restock, false) THEN
    -- Sınırsız stoklu ve dijital ürünlerin stoğuna dokunulmaz.
    UPDATE public.products p
       SET stock_quantity = COALESCE(p.stock_quantity, 0) + x.qty,
           updated_at     = now()
      FROM (SELECT product_id, sum(quantity)::integer AS qty
              FROM public.return_request_items
             WHERE request_id = v_request.id AND product_id IS NOT NULL
             GROUP BY product_id) x
     WHERE p.id = x.product_id
       AND p.shop_id = v_request.shop_id
       AND NOT COALESCE(p.stock_unlimited, false)
       AND COALESCE(p.product_type, 'physical') <> 'digital';
  END IF;

  UPDATE public.return_requests
     SET status      = 'completed',
         received_by = v_uid,
         received_at = now(),
         restocked   = COALESCE(p_restock, false),
         updated_at  = now()
   WHERE id = v_request.id
  RETURNING * INTO v_request;

  v_label := COALESCE((SELECT order_number::text FROM public.orders WHERE id = v_request.order_id),
                      substring(v_request.order_id::text, 1, 8));

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  VALUES (
    v_request.user_id,
    'return_completed',
    'İade Tamamlandı',
    'Sipariş #' || v_label || ' için iade ettiğiniz ürünler satıcıya ulaştı. ' ||
      CASE
        WHEN v_was_paid THEN 'İade süreci tamamlandı.'
        WHEN v_request.refund_method = 'seller_cash'
          THEN '₺' || to_char(v_request.refund_amount, 'FM999999990.00') ||
               ' satıcı tarafından nakit iade edildi.'
        ELSE '₺' || to_char(v_request.refund_amount, 'FM999999990.00') || ' bakiyenize eklendi.'
      END,
    v_request.id::text,
    'return_request',
    jsonb_build_object('request_id', v_request.id, 'order_id', v_request.order_id,
                       'refund_amount', v_request.refund_amount,
                       'balance_transaction_id', v_request.balance_transaction_id)
  );

  RETURN v_request;
END;
$$;

-- ── 4) Yönetici: satıcıyı beklemeden hemen iade ────────────────────────────
DROP FUNCTION IF EXISTS public.admin_refund_return_now(uuid, text);
CREATE FUNCTION public.admin_refund_return_now(
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
  v_was_cash    boolean;
  v_label       text;
  v_note        text := NULLIF(btrim(COALESCE(p_admin_response, '')), '');
  v_item_count  integer;
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
  IF v_request.refunded_at IS NOT NULL THEN
    RAISE EXCEPTION 'Bu iadenin parası zaten ödendi' USING ERRCODE = 'P0001';
  END IF;
  IF v_request.status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'Bu talep % durumunda, iade yapılamaz', v_request.status USING ERRCODE = 'P0001';
  END IF;

  -- Bekleyen talep aynı adımda onaylanır.
  IF v_request.status = 'pending' THEN
    UPDATE public.return_requests
       SET status         = 'approved',
           reviewed_by    = v_admin,
           reviewed_at    = now(),
           admin_response = v_note,
           updated_at     = now()
     WHERE id = v_request.id
    RETURNING * INTO v_request;
  END IF;

  v_was_cash := v_request.refund_method = 'seller_cash';
  v_request  := public.settle_return_request(v_request.id, v_admin, true);

  v_label := COALESCE((SELECT order_number::text FROM public.orders WHERE id = v_request.order_id),
                      substring(v_request.order_id::text, 1, 8));
  SELECT count(*) INTO v_item_count FROM public.return_request_items WHERE request_id = v_request.id;

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  VALUES (
    v_request.user_id,
    'return_approved',
    'İadeniz Yapıldı',
    'Sipariş #' || v_label || ' iadeniz onaylandı ve ₺' ||
      to_char(v_request.refund_amount, 'FM999999990.00') ||
      ' bakiyenize eklendi. Ürünleri satıcıya teslim etmeyi unutmayın.',
    v_request.id::text,
    'return_request',
    jsonb_build_object('request_id', v_request.id, 'order_id', v_request.order_id,
                       'refund_amount', v_request.refund_amount,
                       'balance_transaction_id', v_request.balance_transaction_id,
                       'refunded_by_admin', true)
  );

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  SELECT s.owner_id,
         'return_approved_seller',
         'Yönetici İadeyi Yaptı',
         'Sipariş #' || v_label || ' için ' ||
           CASE WHEN v_request.return_scope = 'full' THEN 'tüm ürünlerin' ELSE v_item_count || ' ürünün' END ||
           ' iadesi onaylandı ve yönetici ₺' || to_char(v_request.refund_amount, 'FM999999990.00') ||
           ' tutarı müşterinin bakiyesine iade etti. ' ||
           CASE WHEN v_was_cash THEN 'Müşteriye nakit VERMEYİN. ' ELSE '' END ||
           '₺' || to_char(v_request.seller_debit_amount, 'FM999999990.00') ||
           ' hesabınızdan düşüldü. Ürünleri müşteriden teslim alınca İade Talepleri ekranından ' ||
           '"Teslim Aldım" deyin.',
         v_request.id::text,
         'return_request',
         jsonb_build_object('request_id', v_request.id, 'order_id', v_request.order_id,
                            'seller_debit_amount', v_request.seller_debit_amount,
                            'commission_refund_amount', v_request.commission_refund_amount,
                            'refunded_by_admin', true)
    FROM public.shops s
   WHERE s.id = v_request.shop_id
     AND s.owner_id IS NOT NULL;

  RETURN v_request;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_refund_return_now(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_refund_return_now(uuid, text) TO authenticated;

-- ── 5) Siparişte iade edilen tutar = parası ödenmiş talepler ───────────────
CREATE OR REPLACE FUNCTION public.refresh_order_return_status(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status   text;
  v_amount   numeric;
  v_full     boolean;
  v_any_done boolean;
BEGIN
  SELECT COALESCE(sum(refund_amount) FILTER (WHERE refunded_at IS NOT NULL
                                               AND status IN ('approved', 'completed')), 0),
         bool_or(status = 'completed')
    INTO v_amount, v_any_done
    FROM public.return_requests
   WHERE order_id = p_order_id;

  v_full := COALESCE(v_any_done, false) AND NOT EXISTS (
    SELECT 1 FROM public.order_items oi
     WHERE oi.order_id = p_order_id
       AND oi.quantity > public.return_completed_quantity(oi.id)
  );

  v_status := CASE
    WHEN v_full THEN 'returned'
    WHEN EXISTS (SELECT 1 FROM public.return_requests
                  WHERE order_id = p_order_id AND status = 'pending') THEN 'requested'
    WHEN EXISTS (SELECT 1 FROM public.return_requests
                  WHERE order_id = p_order_id AND status = 'approved') THEN 'approved'
    WHEN COALESCE(v_any_done, false) THEN 'partially_returned'
    ELSE NULL
  END;

  UPDATE public.orders
     SET return_status = v_status,
         returned_amount = COALESCE(v_amount, 0)
   WHERE id = p_order_id
     AND (return_status IS DISTINCT FROM v_status
          OR returned_amount IS DISTINCT FROM COALESCE(v_amount, 0));
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_order_return_status(uuid) FROM PUBLIC, anon, authenticated;

-- ── 6) Satıcı Genel Bakış iade özeti ───────────────────────────────────────
DROP FUNCTION IF EXISTS public.seller_return_summary();
CREATE FUNCTION public.seller_return_summary()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'pending',        count(*) FILTER (WHERE r.status = 'pending'),
    'awaiting_receipt', count(*) FILTER (WHERE r.status = 'approved'),
    'completed',      count(*) FILTER (WHERE r.status = 'completed'),
    'rejected',       count(*) FILTER (WHERE r.status = 'rejected'),
    'refunded_total', COALESCE(sum(r.refund_amount) FILTER (WHERE r.refunded_at IS NOT NULL
                                                             AND r.status IN ('approved', 'completed')), 0),
    'seller_debit_total', COALESCE(sum(r.seller_debit_amount) FILTER (WHERE r.refunded_at IS NOT NULL
                                                                     AND r.status IN ('approved', 'completed')), 0),
    'returned_items', COALESCE((
       SELECT sum(i.quantity) FROM public.return_request_items i
         JOIN public.return_requests r2 ON r2.id = i.request_id
         JOIN public.shops s2 ON s2.id = r2.shop_id
        WHERE s2.owner_id = auth.uid() AND r2.status = 'completed'), 0)
  )
  FROM public.return_requests r
  JOIN public.shops s ON s.id = r.shop_id
  WHERE s.owner_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.seller_return_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seller_return_summary() TO authenticated;

-- Mevcut siparişlerin tutarını yeni tanıma göre tazele
DO $$
DECLARE
  v_id uuid;
BEGIN
  FOR v_id IN SELECT DISTINCT order_id FROM public.return_requests LOOP
    PERFORM public.refresh_order_return_status(v_id);
  END LOOP;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
