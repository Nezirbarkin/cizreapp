-- ============================================================================
-- İade: para satıcı "teslim aldım" deyince iade edilir + siparişte iade durumu
-- (2026-10-16)
-- ----------------------------------------------------------------------------
-- Kullanıcı isteği:
--   * Yönetici onayı artık PARA HAREKETİ YAPMAZ; yalnız talebi onaylar ve
--     müşteriyle satıcıyı bilgilendirir.
--   * Satıcı (ya da satıcı yerine yönetici) iade edilen ürünleri teslim aldığını
--     onaylayınca (mark_return_received):
--       - balance yöntemi: tutar müşterinin bakiyesine eklenir, satıcıdan
--         (iade − iade edilen tutarın komisyonu) geri alınır;
--       - seller_cash (kuryeli satıcı + kapıda tahsilat): müşteriye nakdi
--         satıcı verir, iade edilen tutarın komisyonu satıcının borcundan düşer.
--     Siparişin tamamı iade edildiyse ödeme 'refunded' olur.
--   * Satıcı ve yönetici ekranlarında iade edilen sipariş belli olsun:
--     orders.return_status ('requested' | 'approved' | 'partially_returned' |
--     'returned') ve orders.returned_amount, return_requests değiştikçe
--     tetikleyiciyle güncellenir. Sipariş durumu (order_status) 'delivered'
--     kalır; kurye/istatistik akışları etkilenmez.
--
-- Önceki onaylarda para zaten hareket ettiyse (balance_transaction_id dolu ya
-- da satıcı/komisyon tutarı yazılı) teslim almada TEKRAR hareket yapılmaz.
-- ============================================================================

BEGIN;

-- ── 1) Siparişte iade durumu ───────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS return_status   text,
  ADD COLUMN IF NOT EXISTS returned_amount numeric(12,2) NOT NULL DEFAULT 0;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_return_status_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_return_status_check
  CHECK (return_status IS NULL
         OR return_status IN ('requested', 'approved', 'partially_returned', 'returned'));

COMMENT ON COLUMN public.orders.return_status IS
  'İade durumu: requested=yönetici incelemesinde, approved=onaylandı/teslim bekleniyor, partially_returned=bazı ürünler iade edildi, returned=tamamı iade edildi.';
COMMENT ON COLUMN public.orders.returned_amount IS
  'Tamamlanan iadelerde müşteriye iade edilen toplam.';

-- Sipariş kaleminde TAMAMLANMIŞ iade adedi
CREATE OR REPLACE FUNCTION public.return_completed_quantity(p_order_item_id uuid)
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
     AND r.status = 'completed';
$$;
REVOKE ALL ON FUNCTION public.return_completed_quantity(uuid) FROM PUBLIC, anon, authenticated;

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
  SELECT COALESCE(sum(refund_amount) FILTER (WHERE status = 'completed'), 0),
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

CREATE OR REPLACE FUNCTION public.trg_return_requests_refresh_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.refresh_order_return_status(NEW.order_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_return_requests_refresh_order ON public.return_requests;
CREATE TRIGGER trg_return_requests_refresh_order
  AFTER INSERT OR UPDATE OF status ON public.return_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_return_requests_refresh_order();

-- ── 2) İade hesabı (teslim anı semantiği) ──────────────────────────────────
-- Bu talep teslim alınınca: adminin vazgeçtiği komisyon, satıcıdan geri
-- alınacak tutar ve siparişin tamamen iade edilmiş olup olmayacağı.
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

  -- Tamamlanmış iadeler + bu talep siparişin bütün ürünlerini kapsıyor mu?
  v_final := NOT EXISTS (
    SELECT 1 FROM public.order_items oi
     WHERE oi.order_id = v_request.order_id
       AND oi.quantity > public.return_completed_quantity(oi.id)
                         + COALESCE((SELECT sum(i.quantity) FROM public.return_request_items i
                                      WHERE i.request_id = v_request.id
                                        AND i.order_item_id = oi.id), 0)
  );

  IF v_request.refund_amount > 0 AND v_goods_paid > 0 THEN
    SELECT COALESCE(sum(commission_refund_amount), 0) INTO v_prev
      FROM public.return_requests
     WHERE order_id = v_request.order_id AND status = 'completed' AND id <> v_request.id;
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

-- ── 3) Yönetici onayı: para hareketi yok ───────────────────────────────────
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
  v_preview     record;
  v_label       text;
  v_note        text := NULLIF(btrim(COALESCE(p_admin_response, '')), '');
  v_item_count  integer;
  v_seller_cash boolean;
  v_amount      text;
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

  SELECT id, shop_id, status::text AS status, payment_status::text AS payment_status, order_number
    INTO v_order
    FROM public.orders WHERE id = v_request.order_id FOR UPDATE;

  IF NOT FOUND OR v_order.status <> 'delivered' THEN
    RAISE EXCEPTION 'Sipariş artık teslim edilmiş durumda değil (iptal edilmiş olabilir); talebi reddedin'
      USING ERRCODE = 'P0001';
  END IF;
  IF v_order.payment_status = 'refunded' THEN
    RAISE EXCEPTION 'Bu siparişin ödemesi zaten iade edilmiş; talebi reddedin' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.return_requests
     SET status         = 'approved',
         reviewed_by    = v_admin,
         reviewed_at    = now(),
         admin_response = v_note,
         updated_at     = now()
   WHERE id = v_request.id
  RETURNING * INTO v_request;

  v_label       := COALESCE(v_order.order_number::text, substring(v_order.id::text, 1, 8));
  v_seller_cash := v_request.refund_method = 'seller_cash';
  v_amount      := to_char(v_request.refund_amount, 'FM999999990.00');
  SELECT * INTO v_preview FROM public.return_settlement_preview(v_request.id);
  SELECT count(*) INTO v_item_count FROM public.return_request_items WHERE request_id = v_request.id;

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  VALUES (
    v_request.user_id,
    'return_approved',
    'İade Talebiniz Onaylandı',
    'Sipariş #' || v_label || ' iadeniz onaylandı. Ürünleri satıcıya teslim edin; ' ||
      CASE WHEN v_seller_cash
           THEN 'teslim ederken ₺' || v_amount || ' iade tutarını satıcıdan nakit alacaksınız.'
           ELSE 'satıcı teslim aldığını onaylayınca ₺' || v_amount || ' bakiyenize eklenecek.'
      END,
    v_request.id::text,
    'return_request',
    jsonb_build_object('request_id', v_request.id, 'order_id', v_order.id,
                       'refund_amount', v_request.refund_amount,
                       'refund_method', v_request.refund_method)
  );

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  SELECT s.owner_id,
         'return_approved_seller',
         'Onaylanan İade',
         'Sipariş #' || v_label || ' için ' ||
           CASE WHEN v_request.return_scope = 'full' THEN 'tüm ürünlerin' ELSE v_item_count || ' ürünün' END ||
           ' iadesi yönetici tarafından onaylandı. Ürünleri müşteriden teslim alınca İade Talepleri ' ||
           'ekranından "Teslim Aldım" deyin. ' ||
           CASE WHEN v_seller_cash
                THEN 'Teslim alırken müşteriye ₺' || v_amount || ' nakit iade edin; onayınızla ₺' ||
                     to_char(v_preview.commission_refund, 'FM999999990.00') ||
                     ' komisyon borcunuzdan düşülür.'
                ELSE 'Onayınızla müşteriye ₺' || v_amount || ' iade edilir, ₺' ||
                     to_char(v_preview.seller_debit, 'FM999999990.00') || ' hesabınızdan düşülür.'
           END,
         v_request.id::text,
         'return_request',
         jsonb_build_object('request_id', v_request.id, 'order_id', v_order.id,
                            'refund_method', v_request.refund_method,
                            'seller_debit_amount', v_preview.seller_debit,
                            'commission_refund_amount', v_preview.commission_refund)
    FROM public.shops s
   WHERE s.id = v_order.shop_id
     AND s.owner_id IS NOT NULL;

  RETURN v_request;
END;
$$;

-- ── 4) Teslim alındı: para burada hareket eder ─────────────────────────────
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
  v_order       record;
  v_preview     record;
  v_shop        record;
  v_from        numeric;
  v_comm        numeric := 0;
  v_debit       numeric := 0;
  v_tx_id       uuid;
  v_label       text;
  v_seller_cash boolean;
  v_settled     boolean;
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

  SELECT id, shop_id, status::text AS status, payment_status::text AS payment_status,
         payment_method::text AS payment_method, commission_status::text AS commission_status,
         order_number
    INTO v_order
    FROM public.orders WHERE id = v_request.order_id FOR UPDATE;

  -- Eski akışta onayda para hareket etmiş olabilir: tekrar yapılmaz.
  v_settled := v_request.balance_transaction_id IS NOT NULL
               OR v_request.seller_debit_amount > 0
               OR v_request.commission_refund_amount > 0;

  IF NOT v_settled THEN
    IF NOT FOUND OR v_order.status <> 'delivered' THEN
      RAISE EXCEPTION 'Sipariş artık teslim edilmiş durumda değil (iptal edilmiş olabilir)'
        USING ERRCODE = 'P0001';
    END IF;
    IF v_order.payment_status = 'refunded' THEN
      RAISE EXCEPTION 'Bu siparişin ödemesi zaten iade edilmiş' USING ERRCODE = 'P0001';
    END IF;

    v_label       := COALESCE(v_order.order_number::text, substring(v_order.id::text, 1, 8));
    v_seller_cash := v_request.refund_method = 'seller_cash';
    SELECT * INTO v_preview FROM public.return_settlement_preview(v_request.id);
    v_comm  := v_preview.commission_refund;
    v_debit := v_preview.seller_debit;

    SELECT id, COALESCE(admin_credit, 0) AS admin_credit,
           COALESCE(commission_debt, 0) AS commission_debt
      INTO v_shop FROM public.shops WHERE id = v_order.shop_id FOR UPDATE;

    IF v_seller_cash THEN
      -- Kuryeli satıcı + kapıda tahsilat: nakdi satıcı iade etti; iade edilen
      -- tutarın komisyonu borcundan düşer (yetmezse kalan alacak olur).
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
      -- Müşteriye bakiye iadesi
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
                                'received_by', v_uid,
                                'order_id', v_order.id,
                                'return_scope', v_request.return_scope,
                                'original_payment_method', v_order.payment_method)
        );
      END IF;

      -- Satıcıdan geri alınan = iade − iade edilen tutarın komisyonu
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

    -- Siparişin tamamı iade edildiyse ödeme 'refunded', bekleyen kazanç iptal
    IF v_preview.is_final THEN
      UPDATE public.orders
         SET payment_status = 'refunded', updated_at = now()
       WHERE id = v_order.id;

      UPDATE public.seller_earnings
         SET status = 'cancelled'
       WHERE order_id = v_order.id
         AND status IN ('pending', 'available');
    END IF;
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
     SET status                   = 'completed',
         received_by              = v_uid,
         received_at              = now(),
         restocked                = COALESCE(p_restock, false),
         balance_transaction_id   = COALESCE(v_tx_id, balance_transaction_id),
         seller_debit_amount      = CASE WHEN v_settled THEN seller_debit_amount ELSE v_debit END,
         commission_refund_amount = CASE WHEN v_settled THEN commission_refund_amount ELSE v_comm END,
         updated_at               = now()
   WHERE id = v_request.id
  RETURNING * INTO v_request;

  v_label := COALESCE(v_order.order_number::text, substring(v_request.order_id::text, 1, 8));

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  VALUES (
    v_request.user_id,
    'return_completed',
    'İade Tamamlandı',
    'Sipariş #' || v_label || ' için iade ettiğiniz ürünler satıcıya ulaştı. ' ||
      CASE
        WHEN v_settled THEN 'İade süreci tamamlandı.'
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

-- ── 5) Mevcut talepler için sipariş iade durumu ────────────────────────────
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
