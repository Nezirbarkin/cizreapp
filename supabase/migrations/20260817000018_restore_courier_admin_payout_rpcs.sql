-- =============================================================================
-- Eksik admin payout/dispute RPC'lerini geri yukle.
--
-- 20260802000005_secure_courier_delivery_and_payout.sql prod'a tam
-- uygulanmamis: paket talebi akisi ve request_courier_payout canli iken
-- admin_approve_courier_payout, admin_reject_courier_payout ve
-- admin_resolve_package_dispute hic olusturulmamis. Sonuc: kurye odeme
-- istegi gonderebiliyor ama admin onaylayamiyor/reddedemiyor (PGRST202),
-- ayni sekilde paket anlasmazligi cozulemiyor.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF to_regclass('public.courier_payout_items') IS NULL THEN
    RAISE EXCEPTION 'public.courier_payout_items tablosu mevcut degil';
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- admin_approve_courier_payout
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_approve_courier_payout(uuid, text);

CREATE FUNCTION public.admin_approve_courier_payout(
  p_payout_id uuid,
  p_payment_reference text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payout public.courier_payout_requests%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_payout_id IS NULL THEN
    RAISE EXCEPTION 'APP:payout_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT cpr.* INTO v_payout
  FROM public.courier_payout_requests AS cpr
  WHERE cpr.id = p_payout_id
  FOR UPDATE;

  IF v_payout.id IS NULL THEN RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001'; END IF;
  IF v_payout.status <> 'pending' THEN
    RAISE EXCEPTION 'APP:invalid_state | durum: %', v_payout.status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.courier_payout_items AS cpi
     SET status = 'paid'
   WHERE cpi.payout_id = p_payout_id;

  UPDATE public.courier_earnings AS ce
     SET status = 'paid'
   WHERE ce.id IN (
     SELECT cpi.earning_id FROM public.courier_payout_items AS cpi
     WHERE cpi.payout_id = p_payout_id
   );

  UPDATE public.courier_payout_requests AS cpr
     SET status = 'approved',
         approved_at = now(),
         approved_by = (SELECT auth.uid()),
         payment_reference = p_payment_reference
   WHERE cpr.id = p_payout_id;

  INSERT INTO public.notifications (user_id, type, title, content, metadata, is_read)
  VALUES (v_payout.courier_id, 'courier_payout_approved',
          'Ödemeniz onaylandı', 'Ödeme talebiniz admin tarafından onaylandı.',
          jsonb_build_object('payout_id', p_payout_id, 'reference', p_payment_reference,
                            'amount', v_payout.amount), false);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_courier_payout(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_courier_payout(uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- admin_reject_courier_payout
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_reject_courier_payout(uuid, text);

CREATE FUNCTION public.admin_reject_courier_payout(
  p_payout_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payout public.courier_payout_requests%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_payout_id IS NULL THEN
    RAISE EXCEPTION 'APP:payout_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT cpr.* INTO v_payout
  FROM public.courier_payout_requests AS cpr
  WHERE cpr.id = p_payout_id
  FOR UPDATE;

  IF v_payout.id IS NULL THEN RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001'; END IF;
  IF v_payout.status <> 'pending' THEN
    RAISE EXCEPTION 'APP:invalid_state' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.courier_payout_items AS cpi
     SET status = 'rejected'
   WHERE cpi.payout_id = p_payout_id;

  UPDATE public.courier_earnings AS ce
     SET status = 'pending'
   WHERE ce.id IN (
     SELECT cpi.earning_id FROM public.courier_payout_items AS cpi
     WHERE cpi.payout_id = p_payout_id
   );

  UPDATE public.courier_payout_requests AS cpr
     SET status = 'rejected',
         rejected_at = now(),
         rejection_reason = p_reason
   WHERE cpr.id = p_payout_id;

  INSERT INTO public.notifications (user_id, type, title, content, metadata, is_read)
  VALUES (v_payout.courier_id, 'courier_payout_rejected',
          'Ödeme isteğiniz reddedildi', 'Gerekçe: ' || coalesce(p_reason, '-'),
          jsonb_build_object('payout_id', p_payout_id, 'reason', p_reason), false);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_courier_payout(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_courier_payout(uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- admin_resolve_package_dispute
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_resolve_package_dispute(uuid, text, boolean);

CREATE FUNCTION public.admin_resolve_package_dispute(
  p_request_id uuid,
  p_resolution text,
  p_confirm boolean
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_rec public.courier_requests%ROWTYPE;
  v_earn_id uuid;
  v_amount  numeric(12, 2);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;

  SELECT cr.* INTO v_rec FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id FOR UPDATE;

  IF v_rec.id IS NULL THEN RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001'; END IF;

  IF p_confirm THEN
    IF v_rec.courier_id IS NULL THEN
      RAISE EXCEPTION 'APP:no_courier' USING ERRCODE = 'P0001';
    END IF;
    IF v_rec.status NOT IN ('accepted', 'delivery_pending_confirmation') THEN
      RAISE EXCEPTION 'APP:invalid_state' USING ERRCODE = 'P0001';
    END IF;
    v_amount := COALESCE(v_rec.courier_fee, 0);

    UPDATE public.courier_requests AS cr
       SET status = 'delivered',
           delivered_at = now(),
           delivery_confirmed_at = now(),
           delivery_confirmed_by = (SELECT auth.uid())
     WHERE cr.id = p_request_id;

    INSERT INTO public.courier_earnings (courier_id, package_request_id, amount, amount_snapshot, status)
    VALUES (v_rec.courier_id, p_request_id, v_amount, v_amount, 'pending')
    ON CONFLICT (package_request_id) WHERE package_request_id IS NOT NULL DO NOTHING
    RETURNING id INTO v_earn_id;

    UPDATE public.profiles AS p
       SET delivered_count = p.delivered_count + 1
     WHERE p.id = v_rec.courier_id;

    INSERT INTO public.notifications (user_id, type, title, content, metadata, is_read)
    VALUES (v_rec.courier_id, 'courier_delivered',
            'Paket teslim edildi (admin)',
            'Paketiniz admin tarafından onaylandı.',
            jsonb_build_object('request_id', p_request_id, 'amount', v_amount, 'reason', p_resolution),
            false);

    RETURN 'delivered';
  ELSE
    UPDATE public.courier_requests AS cr
       SET status = 'cancelled'
     WHERE cr.id = p_request_id;

    INSERT INTO public.notifications (user_id, type, title, content, metadata, is_read)
    VALUES
      (v_rec.courier_id, 'package_dispute_rejected',
       'Paket iptal edildi', 'Admin tarafından iptal edildi: ' || coalesce(p_resolution, ''),
       jsonb_build_object('request_id', p_request_id, 'reason', p_resolution), false),
      (v_rec.sender_id, 'package_dispute_rejected',
       'Paket iptal edildi', 'Admin tarafından iptal edildi: ' || coalesce(p_resolution, ''),
       jsonb_build_object('request_id', p_request_id, 'reason', p_resolution), false);

    RETURN 'cancelled';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_resolve_package_dispute(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_package_dispute(uuid, text, boolean) TO authenticated;

COMMENT ON FUNCTION public.admin_approve_courier_payout(uuid, text) IS
  'Bekleyen kurye odeme istegini onaylar; bagli tum payout item ve earnings satirlarini paid yapar.';
COMMENT ON FUNCTION public.admin_reject_courier_payout(uuid, text) IS
  'Bekleyen kurye odeme istegini reddeder; bagli earnings satirlarini pending''e geri dondurur.';
COMMENT ON FUNCTION public.admin_resolve_package_dispute(uuid, text, boolean) IS
  'Admin, ihtilafli paket teslimatini onaylar (earnings olusturur) veya iptal eder.';

NOTIFY pgrst, 'reload schema';
