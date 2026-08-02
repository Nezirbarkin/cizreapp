-- 20260802000010_order_state_machine_rpc.sql
-- Tarih: 2026-08-02
-- Server-authoritative sipariş durum makinesi
-- 4 RPC: cancel_order, mark_paid (admin/service), mark_shipped, mark_delivered
-- Tüm geçişler FOR UPDATE + allowed listesi + audit trigger.

SET search_path = public, private;

-- ════════════════════════════════════════════════════════════════════════
-- cancel_order — kullanıcı kendi siparişini iptal edebilir
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order RECORD;
  v_audit JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required | oturum gerekli' USING ERRCODE = 'P0001';
  END IF;

  SELECT id, user_id, status, payment_status, total, coupon_id, order_group_id
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:order_not_found | sipariş yok' USING ERRCODE = 'P0001';
  END IF;

  IF v_order.user_id <> v_user_id THEN
    RAISE EXCEPTION 'APP:forbidden | yetkisiz' USING ERRCODE = 'P0001';
  END IF;

  -- Durum makinesi: yalnız 'pending' ve 'confirmed' iptal edilebilir
  IF v_order.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'APP:cancel_not_allowed | durum: %', v_order.status USING ERRCODE = 'P0001';
  END IF;

  -- payment_status 'paid' ise iptal için admin gerekli
  IF v_order.payment_status = 'paid' THEN
    RAISE EXCEPTION 'APP:cancel_paid_forbidden | ödeme alınmış, iade gerekli' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_at = now(),
      cancel_reason = p_reason
  WHERE id = p_order_id;

  v_audit := jsonb_build_object(
    'event', 'order_cancelled',
    'order_id', p_order_id,
    'previous_status', v_order.status,
    'reason', p_reason
  );

  INSERT INTO private.server_checkout_audit (event_type, user_id, order_id, payload)
  VALUES ('order_cancelled', v_user_id, p_order_id, v_audit);

  RETURN v_audit;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_order(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_order(UUID, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════
-- mark_paid — service_role/admin (online ödeme callback'i başarıyla
--   commit_online_order içinde payment_status='paid' yapar; bu RPC
--   yalnızca manuel admin işlemleri içindir)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION private.mark_order_paid(
  p_order_id UUID,
  p_payment_transaction_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status, payment_status INTO v_status
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:order_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_status IN ('cancelled', 'delivered', 'refunded') THEN
    RAISE EXCEPTION 'APP:transition_not_allowed | %', v_status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
  SET payment_status = 'paid',
      status = CASE WHEN status = 'pending' THEN 'confirmed' ELSE status END,
      paid_at = COALESCE(paid_at, now()),
      payment_transaction_id = p_payment_transaction_id
  WHERE id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION private.mark_order_paid(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.mark_order_paid(UUID, UUID) TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- mark_shipped — service_role (kargo şirketi webhook veya admin panel)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION private.mark_order_shipped(
  p_order_id UUID,
  p_tracking_url TEXT DEFAULT NULL,
  p_cargo_company TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status FROM public.orders
  WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:order_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'APP:transition_not_allowed | %', v_status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
  SET status = 'shipped',
      tracking_url = COALESCE(p_tracking_url, tracking_url),
      cargo_company = COALESCE(p_cargo_company, cargo_company),
      shipped_at = now()
  WHERE id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION private.mark_order_shipped(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.mark_order_shipped(UUID, TEXT, TEXT) TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- mark_delivered — service_role
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION private.mark_order_delivered(
  p_order_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status FROM public.orders
  WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:order_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_status <> 'shipped' THEN
    RAISE EXCEPTION 'APP:transition_not_allowed | %', v_status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders
  SET status = 'delivered',
      delivered_at = now()
  WHERE id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION private.mark_order_delivered(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.mark_order_delivered(UUID) TO service_role;
