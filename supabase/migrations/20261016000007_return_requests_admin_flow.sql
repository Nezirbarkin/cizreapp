-- ============================================================================
-- Müşteri iadesi: tümü veya seçili ürünler + yönetici onaylı akış (2026-10-16)
-- ----------------------------------------------------------------------------
-- Eski durum (20260411000002) ve hataları:
--   * İstemci return_requests'e doğrudan INSERT ediyordu; politika yalnız
--     user_id = auth.uid() bakıyordu → herkes BAŞKASININ veya teslim edilmemiş
--     bir sipariş için iade talebi açabiliyordu.
--   * Satıcı talebi doğrudan onaylayıp "tamamlandı" yapabiliyordu; yönetici
--     adımı yoktu, para iadesi hiç yapılmıyordu, kimseye bildirim gitmiyordu.
--   * Ürün seçimi yoktu (yalnız tüm sipariş) ve sipariş başına TEK talep
--     sınırı vardı (reddedilen talepten sonra yeniden talep açılamıyordu).
--   * Satıcı ekranı profiles(name) gömüyordu; return_requests.user_id
--     auth.users'a bağlı olduğundan PostgREST ilişkiyi bulamıyor, liste her
--     zaman boş dönüyordu (hata yutuluyordu).
--
-- Yeni akış:
--   1) Müşteri (teslim edilmiş, 14 gün içindeki sipariş) create_return_request
--      ile tümünü ya da seçili ürün/adetleri iade ister → status 'pending',
--      yöneticilere bildirim.
--   2) Yönetici approve_return_request:
--        - iade tutarı müşterinin CizreApp bakiyesine eklenir (ödeme yöntemi
--          ne olursa olsun; teslim edilmiş siparişin parası alınmıştır),
--        - satıcının bu tutardaki payı mağaza hesabından düşülür,
--        - müşteriye ve satıcıya bildirim gider. → status 'approved'.
--      reject_return_request → 'rejected', müşteriye bildirim.
--   3) Satıcı (veya yönetici) ürünü teslim alınca mark_return_received →
--      'completed'; isterse ürünler stoğa geri eklenir; müşteriye bildirim.
--   4) Müşteri bekleyen talebini cancel_return_request ile geri çekebilir.
--
-- Tutar kuralları:
--   * Kalem değeri = order_items.subtotal / quantity × iade adedi.
--   * Kupon/indirim orantılı düşülür: oran = (total − delivery_fee) /
--     Σ kalem subtotal (en fazla 1). Teslimat ücreti iade edilmez.
--   * Siparişin kalan son ürünlerini iade eden talep, kalan iade edilebilir
--     tutarın TAMAMINI alır (kuruş yuvarlama kayması olmasın).
--   * Satıcı payı = iade × seller_net_amount / total (0..1 arası).
--
-- Bilerek yapılmayanlar: kurye kazancı ve products.sales_count geri alınmaz;
-- gönderilmiş/onaylı fatura için sağlayıcıda iade faturası ayrıca gerekir.
-- ============================================================================

BEGIN;

-- ── 1) Tablo genişletme ─────────────────────────────────────────────────────
ALTER TABLE public.return_requests
  ADD COLUMN IF NOT EXISTS return_scope            text NOT NULL DEFAULT 'full',
  ADD COLUMN IF NOT EXISTS payment_method          text,
  ADD COLUMN IF NOT EXISTS refund_amount           numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS seller_debit_amount     numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS balance_transaction_id  uuid,
  ADD COLUMN IF NOT EXISTS reviewed_by             uuid,
  ADD COLUMN IF NOT EXISTS reviewed_at             timestamptz,
  ADD COLUMN IF NOT EXISTS received_by             uuid,
  ADD COLUMN IF NOT EXISTS received_at             timestamptz,
  ADD COLUMN IF NOT EXISTS restocked               boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS cancelled_at            timestamptz;

ALTER TABLE public.return_requests
  DROP CONSTRAINT IF EXISTS return_requests_status_check;
ALTER TABLE public.return_requests
  ADD CONSTRAINT return_requests_status_check
  CHECK (status IN ('pending', 'approved', 'rejected', 'completed', 'cancelled'));

ALTER TABLE public.return_requests
  DROP CONSTRAINT IF EXISTS return_requests_scope_check;
ALTER TABLE public.return_requests
  ADD CONSTRAINT return_requests_scope_check
  CHECK (return_scope IN ('full', 'partial'));

-- Sipariş başına tek talep yerine: aynı anda yalnız bir BEKLEYEN talep.
DROP INDEX IF EXISTS public.idx_return_requests_order_unique;
CREATE UNIQUE INDEX IF NOT EXISTS idx_return_requests_order_pending_unique
  ON public.return_requests(order_id)
  WHERE status = 'pending';

COMMENT ON COLUMN public.return_requests.refund_amount IS
  'Müşteriye bakiyeye iade edilecek/edilen tutar (talep anında hesaplanır).';
COMMENT ON COLUMN public.return_requests.seller_debit_amount IS
  'Onayda satıcının mağaza hesabından düşülen pay.';

-- ── 2) Kalem tablosu ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.return_request_items (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id         uuid NOT NULL REFERENCES public.return_requests(id) ON DELETE CASCADE,
  order_item_id      uuid NOT NULL REFERENCES public.order_items(id) ON DELETE CASCADE,
  product_id         uuid,
  product_name       text NOT NULL,
  product_image_url  text,
  quantity           integer NOT NULL CHECK (quantity > 0),
  unit_price         numeric(12,2) NOT NULL,
  line_total         numeric(12,2) NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, order_item_id)
);

CREATE INDEX IF NOT EXISTS idx_return_request_items_order_item
  ON public.return_request_items(order_item_id);

ALTER TABLE public.return_request_items ENABLE ROW LEVEL SECURITY;

-- Kalemler, üst talebi görebilen herkese görünür (üst tablonun RLS'i alt
-- sorguda da uygulanır).
DROP POLICY IF EXISTS "return_request_items_select" ON public.return_request_items;
CREATE POLICY "return_request_items_select"
  ON public.return_request_items
  FOR SELECT
  TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.return_requests r WHERE r.id = request_id
  ));

REVOKE ALL ON public.return_request_items FROM anon, authenticated;
GRANT SELECT ON public.return_request_items TO authenticated;

-- ── 3) Doğrudan yazma kapanır: her şey RPC üzerinden ───────────────────────
DROP POLICY IF EXISTS "Users can create return requests" ON public.return_requests;
DROP POLICY IF EXISTS "Allow update based on role" ON public.return_requests;

REVOKE ALL ON public.return_requests FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.return_requests FROM authenticated;
GRANT SELECT ON public.return_requests TO authenticated;

-- ── 4) Eski (kalemsiz) talepler: tüm sipariş iadesi olarak tamamlanır ──────
INSERT INTO public.return_request_items (
  request_id, order_item_id, product_id, product_name, product_image_url,
  quantity, unit_price, line_total
)
SELECT r.id, oi.id, oi.product_id, COALESCE(oi.product_name, 'Ürün'),
       oi.product_image_url, oi.quantity,
       round(COALESCE(oi.subtotal, oi.price * oi.quantity) / NULLIF(oi.quantity, 0), 2),
       COALESCE(oi.subtotal, oi.price * oi.quantity)
  FROM public.return_requests r
  JOIN public.order_items oi ON oi.order_id = r.order_id
 WHERE oi.quantity > 0
   AND NOT EXISTS (SELECT 1 FROM public.return_request_items x WHERE x.request_id = r.id);

UPDATE public.return_requests r
   SET payment_method = o.payment_method::text,
       return_scope   = 'full',
       refund_amount  = CASE WHEN r.status = 'pending'
                             THEN GREATEST(COALESCE(o.total, 0) - COALESCE(o.delivery_fee, 0), 0)
                             ELSE r.refund_amount END
  FROM public.orders o
 WHERE o.id = r.order_id
   AND r.payment_method IS NULL;

-- ── 5) Yardımcı: sipariş kaleminin iade sürecindeki adedi ──────────────────
CREATE OR REPLACE FUNCTION public.return_reserved_quantity(p_order_item_id uuid)
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
     AND r.status IN ('pending', 'approved', 'completed');
$$;

REVOKE ALL ON FUNCTION public.return_reserved_quantity(uuid) FROM PUBLIC, anon, authenticated;

-- ── 6) Müşteri: iade talebi aç ─────────────────────────────────────────────
-- p_items: NULL / [] = kalan tüm ürünler; yoksa
--          [{"order_item_id": "...", "quantity": 2}, ...]
DROP FUNCTION IF EXISTS public.create_return_request(uuid, text, jsonb);
CREATE FUNCTION public.create_return_request(
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
         order_number, delivered_at, updated_at, created_at
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
    payment_method, refund_amount, created_at
  ) VALUES (
    p_order_id, v_uid, v_order.shop_id, v_reason, 'pending', v_scope,
    v_order.payment_method, v_refund, now()
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

-- ── 7) Yönetici: onayla (para iadesi + satıcı payı + bildirimler) ──────────
DROP FUNCTION IF EXISTS public.approve_return_request(uuid, text);
CREATE FUNCTION public.approve_return_request(
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
  v_share       numeric;
  v_debit       numeric := 0;
  v_prev_debit  numeric;
  v_final       boolean;
  v_shop        record;
  v_from_credit numeric;
  v_tx_id       uuid;
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
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'Bu talep zaten % durumunda, tekrar işlenemez', v_request.status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT id, shop_id, user_id, status::text AS status, payment_status::text AS payment_status,
         payment_method::text AS payment_method, commission_status::text AS commission_status,
         total, seller_net_amount, order_number
    INTO v_order
    FROM public.orders WHERE id = v_request.order_id FOR UPDATE;

  IF NOT FOUND OR v_order.status <> 'delivered' THEN
    RAISE EXCEPTION 'Sipariş artık teslim edilmiş durumda değil (iptal edilmiş olabilir); talebi reddedin'
      USING ERRCODE = 'P0001';
  END IF;
  IF v_order.payment_status = 'refunded' THEN
    RAISE EXCEPTION 'Bu siparişin ödemesi zaten iade edilmiş; talebi reddedin' USING ERRCODE = 'P0001';
  END IF;

  v_label := COALESCE(v_order.order_number::text, substring(v_order.id::text, 1, 8));

  -- Bu talep onaylanınca siparişte iade edilmemiş ürün kalıyor mu?
  v_final := NOT EXISTS (
    SELECT 1 FROM public.order_items oi
     WHERE oi.order_id = v_order.id
       AND oi.quantity > public.return_reserved_quantity(oi.id)
  );

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

  -- 2) Satıcı payını mağaza hesabından düş
  IF COALESCE(v_order.total, 0) > 0 AND v_request.refund_amount > 0 THEN
    v_share := LEAST(GREATEST(COALESCE(v_order.seller_net_amount, v_order.total) / v_order.total, 0), 1);
    IF v_final THEN
      SELECT COALESCE(sum(seller_debit_amount), 0) INTO v_prev_debit
        FROM public.return_requests
       WHERE order_id = v_order.id AND status IN ('approved', 'completed');
      v_debit := GREATEST(COALESCE(v_order.seller_net_amount, v_order.total) - v_prev_debit, 0);
      v_debit := LEAST(v_debit, v_request.refund_amount);
    ELSE
      v_debit := round(v_request.refund_amount * v_share, 2);
    END IF;
  END IF;

  IF v_debit > 0 THEN
    SELECT id, owner_id, COALESCE(admin_credit, 0) AS admin_credit
      INTO v_shop FROM public.shops WHERE id = v_order.shop_id FOR UPDATE;

    IF FOUND THEN
      IF v_order.commission_status = 'cash_collected' THEN
        -- Nakdi satıcı tuttu: iade edilen payı platforma borçlanır.
        UPDATE public.shops
           SET commission_debt      = COALESCE(commission_debt, 0) + v_debit,
               cash_payment_revenue = GREATEST(COALESCE(cash_payment_revenue, 0) - v_debit, 0),
               updated_at           = now()
         WHERE id = v_shop.id;
      ELSE
        -- Platformun satıcıya olan alacağından düş; yetmezse kalan borç olur.
        v_from_credit := LEAST(GREATEST(v_shop.admin_credit, 0), v_debit);
        UPDATE public.shops
           SET admin_credit    = COALESCE(admin_credit, 0) - v_from_credit,
               commission_debt = COALESCE(commission_debt, 0) + (v_debit - v_from_credit),
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
     SET status                 = 'approved',
         reviewed_by            = v_admin,
         reviewed_at            = now(),
         admin_response         = v_note,
         balance_transaction_id = v_tx_id,
         seller_debit_amount    = v_debit,
         updated_at             = now()
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
      CASE WHEN v_request.refund_amount > 0
           THEN ' ₺' || to_char(v_request.refund_amount, 'FM999999990.00') || ' bakiyenize eklendi.'
           ELSE '' END ||
      ' Ürünleri satıcıya teslim etmeyi unutmayın.',
    v_request.id::text,
    'return_request',
    jsonb_build_object('request_id', v_request.id, 'order_id', v_order.id,
                       'refund_amount', v_request.refund_amount,
                       'balance_transaction_id', v_tx_id)
  );

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  SELECT s.owner_id,
         'return_approved_seller',
         'Onaylanan İade',
         'Sipariş #' || v_label || ' için ' ||
           CASE WHEN v_request.return_scope = 'full' THEN 'tüm ürünlerin' ELSE v_item_count || ' ürünün' END ||
           ' iadesi yönetici tarafından onaylandı.' ||
           CASE WHEN v_debit > 0
                THEN ' ₺' || to_char(v_debit, 'FM999999990.00') || ' hesabınızdan düşüldü.'
                ELSE '' END ||
           ' Ürünleri teslim alınca İade Talepleri ekranından onaylayın.',
         v_request.id::text,
         'return_request',
         jsonb_build_object('request_id', v_request.id, 'order_id', v_order.id,
                            'seller_debit_amount', v_debit)
    FROM public.shops s
   WHERE s.id = v_order.shop_id
     AND s.owner_id IS NOT NULL;

  RETURN v_request;
END;
$$;

-- ── 8) Yönetici: reddet ────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.reject_return_request(uuid, text);
CREATE FUNCTION public.reject_return_request(
  p_request_id     uuid,
  p_admin_response text
) RETURNS public.return_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin   uuid := auth.uid();
  v_request public.return_requests;
  v_note    text := btrim(COALESCE(p_admin_response, ''));
  v_label   text;
BEGIN
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
  END IF;
  IF length(v_note) < 3 THEN
    RAISE EXCEPTION 'Red gerekçesi en az 3 karakter olmalı' USING ERRCODE = '22023';
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

  UPDATE public.return_requests
     SET status = 'rejected', reviewed_by = v_admin, reviewed_at = now(),
         admin_response = v_note, updated_at = now()
   WHERE id = v_request.id
  RETURNING * INTO v_request;

  v_label := COALESCE((SELECT order_number::text FROM public.orders WHERE id = v_request.order_id),
                      substring(v_request.order_id::text, 1, 8));

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  VALUES (
    v_request.user_id,
    'return_rejected',
    'İade Talebiniz Reddedildi',
    'Sipariş #' || v_label || ' iade talebiniz reddedildi. Gerekçe: ' || v_note,
    v_request.id::text,
    'return_request',
    jsonb_build_object('request_id', v_request.id, 'order_id', v_request.order_id)
  );

  RETURN v_request;
END;
$$;

-- ── 9) Satıcı/yönetici: ürünler teslim alındı (isteğe bağlı stoğa ekle) ────
DROP FUNCTION IF EXISTS public.mark_return_received(uuid, boolean);
CREATE FUNCTION public.mark_return_received(
  p_request_id uuid,
  p_restock    boolean DEFAULT false
) RETURNS public.return_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_request public.return_requests;
  v_label   text;
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
     SET status = 'completed', received_by = v_uid, received_at = now(),
         restocked = COALESCE(p_restock, false), updated_at = now()
   WHERE id = v_request.id
  RETURNING * INTO v_request;

  v_label := COALESCE((SELECT order_number::text FROM public.orders WHERE id = v_request.order_id),
                      substring(v_request.order_id::text, 1, 8));

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata)
  VALUES (
    v_request.user_id,
    'return_completed',
    'İade Tamamlandı',
    'Sipariş #' || v_label || ' için iade ettiğiniz ürünler satıcıya ulaştı. İade süreci tamamlandı.',
    v_request.id::text,
    'return_request',
    jsonb_build_object('request_id', v_request.id, 'order_id', v_request.order_id)
  );

  RETURN v_request;
END;
$$;

-- ── 10) Müşteri: bekleyen talebi geri çek ──────────────────────────────────
DROP FUNCTION IF EXISTS public.cancel_return_request(uuid);
CREATE FUNCTION public.cancel_return_request(p_request_id uuid)
RETURNS public.return_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_request public.return_requests;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request FROM public.return_requests
   WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_request.user_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'İade talebi bulunamadı' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'Yalnızca bekleyen talepler geri çekilebilir' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.return_requests
     SET status = 'cancelled', cancelled_at = now(), updated_at = now()
   WHERE id = v_request.id
  RETURNING * INTO v_request;

  -- Yöneticilerin "yeni iade talebi" bildirimi artık geçersiz.
  DELETE FROM public.notifications
   WHERE type = 'return_request' AND entity_id = v_request.id::text;

  RETURN v_request;
END;
$$;

-- ── 11) Liste: müşteri / satıcı / yönetici (adlar + kalemler tek istekte) ──
DROP FUNCTION IF EXISTS public.get_return_requests(text, text, uuid);
CREATE FUNCTION public.get_return_requests(
  p_scope    text,
  p_status   text DEFAULT NULL,
  p_order_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;
  IF p_scope NOT IN ('customer', 'seller', 'admin') THEN
    RAISE EXCEPTION 'Geçersiz kapsam' USING ERRCODE = '22023';
  END IF;
  IF p_scope = 'admin' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT r.created_at,
             to_jsonb(r) || jsonb_build_object(
               'order_number', o.order_number,
               'order_total', o.total,
               'shop_name', s.name,
               'customer_name', CASE WHEN p_scope = 'customer' THEN NULL
                                     ELSE COALESCE(NULLIF(btrim(pr.full_name), ''), pr.username) END,
               'items', COALESCE((
                 SELECT jsonb_agg(to_jsonb(i) ORDER BY i.product_name)
                   FROM public.return_request_items i
                  WHERE i.request_id = r.id), '[]'::jsonb)
             ) AS row_data
        FROM public.return_requests r
        JOIN public.orders o ON o.id = r.order_id
        LEFT JOIN public.shops s ON s.id = r.shop_id
        LEFT JOIN public.profiles pr ON pr.id = r.user_id
       WHERE (p_status IS NULL OR r.status = p_status)
         AND (p_order_id IS NULL OR r.order_id = p_order_id)
         AND CASE p_scope
               WHEN 'customer' THEN r.user_id = v_uid
               WHEN 'seller'   THEN s.owner_id = v_uid
               ELSE true
             END
       ORDER BY r.created_at DESC
       LIMIT 200
    ) t;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_return_request(uuid, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_return_request(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_return_request(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_return_received(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_return_request(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_return_requests(text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_return_request(uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_return_request(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_return_request(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_return_received(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_return_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_return_requests(text, text, uuid) TO authenticated;

-- ── 12) Çifte iade koruması: onaylı iadesi olan sipariş admin iptaline kapalı
-- Aksi halde admin_cancel_with_refund siparişin TAMAMINI yeniden iade eder ve
-- update_shop_balance satıcı payını ikinci kez düşerdi.
CREATE OR REPLACE FUNCTION public.guard_cancel_after_return()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status = 'delivered'
     AND EXISTS (SELECT 1 FROM public.return_requests
                  WHERE order_id = NEW.id AND status IN ('approved', 'completed')) THEN
    RAISE EXCEPTION 'Bu siparişte onaylanmış iade var; iptal yerine iade akışını kullanın'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_guard_cancel_after_return ON public.orders;
CREATE TRIGGER trg_orders_guard_cancel_after_return
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status IS DISTINCT FROM OLD.status)
  EXECUTE FUNCTION public.guard_cancel_after_return();

COMMIT;

NOTIFY pgrst, 'reload schema';
