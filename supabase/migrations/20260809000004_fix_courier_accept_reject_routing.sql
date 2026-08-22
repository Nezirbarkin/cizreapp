-- ============================================================================
-- Kurye paket kabul RPC cache düzeltmesi + güvenli ret/yönlendirme akışı
-- ============================================================================

-- Bir siparişi reddeden kuryeye aynı siparişin tekrar atanmasını engeller.
CREATE TABLE IF NOT EXISTS public.courier_order_rejections (
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rejected_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (order_id, courier_id)
);

CREATE INDEX IF NOT EXISTS idx_courier_order_rejections_courier
  ON public.courier_order_rejections (courier_id);

ALTER TABLE public.courier_order_rejections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.courier_order_rejections FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.courier_order_rejections TO service_role;

-- Paket kabul e-postalarının tekrar gönderilmesini önleyen sunucu kayıt tablosu.
CREATE TABLE IF NOT EXISTS public.courier_package_email_deliveries (
  request_id uuid PRIMARY KEY REFERENCES public.courier_requests(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sent', 'failed')),
  last_error text,
  attempted_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz
);

ALTER TABLE public.courier_package_email_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.courier_package_email_deliveries
  FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.courier_package_email_deliveries TO service_role;

-- PGRST202 görülen imzayı deterministik şekilde yeniden oluştur.
DROP FUNCTION IF EXISTS public.accept_package_request(uuid);

CREATE FUNCTION public.accept_package_request(p_request_id uuid)
RETURNS TABLE(
  r_id uuid,
  r_status text,
  r_courier_id uuid,
  r_courier_fee numeric,
  r_admin_commission numeric,
  r_accepted_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_rec public.courier_requests%ROWTYPE;
  v_total numeric(12, 2);
  v_fee numeric(12, 2);
  v_admin numeric(12, 2);
  v_accepted_at timestamptz := clock_timestamp();
  v_commission_percent numeric := 20;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'APP:request_id_required' USING ERRCODE = '22023';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye rolü gerekli' USING ERRCODE = '42501';
  END IF;

  SELECT cr.* INTO v_rec
  FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id
  FOR UPDATE;

  IF v_rec.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_rec.status <> 'pending' OR v_rec.courier_id IS NOT NULL THEN
    RAISE EXCEPTION 'APP:already_taken | talep zaten alınmış'
      USING ERRCODE = 'P0001';
  END IF;
  IF v_rec.sender_id = v_uid THEN
    RAISE EXCEPTION 'APP:self_accept_forbidden' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.courier_request_rejections AS crr
    WHERE crr.request_id = p_request_id AND crr.courier_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:previously_rejected | reddedilen talep kabul edilemez'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(css.commission_percent, 20)
    INTO v_commission_percent
  FROM public.courier_service_settings AS css
  WHERE css.enabled = true
  ORDER BY css.updated_at DESC NULLS LAST
  LIMIT 1;

  v_total := v_rec.total_fee;
  v_fee := round(v_total * (1 - COALESCE(v_commission_percent, 20) / 100.0), 2);
  v_admin := v_total - v_fee;

  UPDATE public.courier_requests AS cr
  SET status = 'accepted',
      courier_id = v_uid,
      courier_fee = v_fee,
      admin_commission = v_admin,
      accepted_at = v_accepted_at
  WHERE cr.id = p_request_id;

  -- Gönderici bildirimi artık eksik PII içeren istemci nesnesine bağlı değildir.
  PERFORM public.add_notification(
    p_user_id => v_rec.sender_id,
    p_type => 'courier_assigned',
    p_title => 'Kurye Atandı',
    p_content => 'Paket talebiniz bir kurye tarafından kabul edildi.',
    p_entity_id => p_request_id::text
  );

  RETURN QUERY
  SELECT p_request_id, 'accepted'::text, v_uid, v_fee, v_admin, v_accepted_at;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_package_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_package_request(uuid) TO authenticated;

COMMENT ON FUNCTION public.accept_package_request(uuid) IS
  'Paketi atomik kabul eder; önce reddeden kuryeyi engeller ve göndericiyi bildirir.';

-- Paket reddedildiğinde mevcut kurye havuzundan sıradaki uygun kuryeyi bulup
-- bildirir. Talep pending kalır; böylece yeni kurye açıkça kabul etmeden finansal
-- sorumluluk üstlenmez.
DROP FUNCTION IF EXISTS public.reject_package_request(uuid);

CREATE FUNCTION public.reject_package_request(p_request_id uuid)
RETURNS TABLE(r_next_courier_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_rec public.courier_requests%ROWTYPE;
  v_next_courier_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'APP:request_id_required' USING ERRCODE = '22023';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT cr.* INTO v_rec
  FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id
  FOR UPDATE;

  IF v_rec.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_rec.status <> 'pending' OR v_rec.courier_id IS NOT NULL THEN
    RAISE EXCEPTION 'APP:not_pending' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.courier_request_rejections (request_id, courier_id)
  VALUES (p_request_id, v_uid)
  ON CONFLICT DO NOTHING;

  UPDATE public.courier_requests AS cr
  SET rejected_by = ARRAY(
    SELECT DISTINCT rejected_id
    FROM unnest(COALESCE(cr.rejected_by, ARRAY[]::uuid[]) || ARRAY[v_uid])
      AS rejected_id
  )
  WHERE cr.id = p_request_id;

  SELECT p.id INTO v_next_courier_id
  FROM public.profiles AS p
  WHERE p.role = 'courier'
    AND p.id <> v_rec.sender_id
    AND p.id <> v_uid
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_request_rejections AS crr
      WHERE crr.request_id = p_request_id AND crr.courier_id = p.id
    )
  ORDER BY COALESCE(p.is_online, false) DESC,
           COALESCE(p.delivered_count, 0) ASC,
           p.id
  LIMIT 1;

  IF v_next_courier_id IS NOT NULL THEN
    PERFORM public.add_notification(
      p_user_id => v_next_courier_id,
      p_type => 'new_package_request',
      p_title => 'Yeni Paket Talebi',
      p_content => 'Bir paket talebi size yönlendirildi. Kurye panelinden inceleyebilirsiniz.',
      p_entity_id => p_request_id::text
    );
  END IF;

  RETURN QUERY SELECT v_next_courier_id;
END;
$$;

REVOKE ALL ON FUNCTION public.reject_package_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_package_request(uuid) TO authenticated;

-- Atanmış fakat henüz alınmamış siparişi reddeder ve aynı atomik işlemde
-- daha önce reddetmemiş sıradaki kuryeye aktarır.
CREATE OR REPLACE FUNCTION public.reject_order_assignment(p_assignment_id uuid)
RETURNS TABLE(
  r_assignment_id uuid,
  r_next_courier_id uuid,
  r_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_assignment public.courier_assignments%ROWTYPE;
  v_next_courier_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_assignment_id IS NULL THEN
    RAISE EXCEPTION 'APP:assignment_id_required' USING ERRCODE = '22023';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT ca.* INTO v_assignment
  FROM public.courier_assignments AS ca
  WHERE ca.id = p_assignment_id
  FOR UPDATE;

  IF v_assignment.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_assignment.courier_id <> v_uid THEN
    RAISE EXCEPTION 'APP:not_assignment_owner' USING ERRCODE = '42501';
  END IF;
  IF v_assignment.status <> 'assigned' THEN
    RAISE EXCEPTION 'APP:cannot_reject_after_pickup' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.courier_order_rejections (order_id, courier_id)
  VALUES (v_assignment.order_id, v_uid)
  ON CONFLICT DO NOTHING;

  SELECT p.id INTO v_next_courier_id
  FROM public.profiles AS p
  WHERE p.role = 'courier'
    AND p.id <> v_uid
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_order_rejections AS cor
      WHERE cor.order_id = v_assignment.order_id AND cor.courier_id = p.id
    )
  ORDER BY COALESCE(p.is_online, false) DESC,
           COALESCE(p.delivered_count, 0) ASC,
           p.id
  LIMIT 1;

  -- Yeni kurye siparişi kabul etmeden "yolda" görünmemeli.
  UPDATE public.orders AS o
  SET status = CASE WHEN o.status = 'on_the_way' THEN 'ready' ELSE o.status END,
      updated_at = now()
  WHERE o.id = v_assignment.order_id;

  IF v_next_courier_id IS NULL THEN
    UPDATE public.courier_assignments AS ca
    SET status = 'cancelled'
    WHERE ca.id = p_assignment_id;

    RETURN QUERY SELECT p_assignment_id, NULL::uuid, 'available'::text;
    RETURN;
  END IF;

  UPDATE public.courier_assignments AS ca
  SET courier_id = v_next_courier_id,
      status = 'assigned',
      assigned_at = now()
  WHERE ca.id = p_assignment_id;

  PERFORM public.add_notification(
    p_user_id => v_next_courier_id,
    p_type => 'courier_order_assigned',
    p_title => 'Sipariş Sana Atandı',
    p_content => 'Bir sipariş size yeniden yönlendirildi. Kurye panelinden inceleyebilirsiniz.',
    p_entity_id => v_assignment.order_id::text
  );

  RETURN QUERY
  SELECT p_assignment_id, v_next_courier_id, 'reassigned'::text;
END;
$$;

REVOKE ALL ON FUNCTION public.reject_order_assignment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_order_assignment(uuid) TO authenticated;

COMMENT ON FUNCTION public.reject_order_assignment(uuid) IS
  'Kurye sipariş reddini kaydeder ve siparişi atomik olarak sıradaki uygun kuryeye yönlendirir.';

-- Yeni/değişen RPC imzalarını PostgREST şema cache'ine bildir.
NOTIFY pgrst, 'reload schema';

