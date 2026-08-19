-- ============================================================================
-- Devredilen kurye işlerini hedef kuryenin "Atanabilir" ekranına taşı
-- ve Paket+ tekliflerine güvenli alım/teslim bilgisi ekle.
--
-- Sipariş devri:
--   reject -> hedef kuryeye pending offer -> açık kabul -> aktif sipariş
-- Paket yönlendirmesi:
--   route/reject -> hedef kuryeye pending offer -> açık kabul -> aktif paket
-- ============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.courier_work_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_type text NOT NULL CHECK (work_type IN ('order', 'package')),
  order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE,
  package_request_id uuid REFERENCES public.courier_requests(id) ON DELETE CASCADE,
  assignment_id uuid REFERENCES public.courier_assignments(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'rejected', 'expired')),
  offered_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  CONSTRAINT courier_work_offers_entity_check CHECK (
    (work_type = 'order'
      AND order_id IS NOT NULL
      AND assignment_id IS NOT NULL
      AND package_request_id IS NULL)
    OR
    (work_type = 'package'
      AND package_request_id IS NOT NULL
      AND order_id IS NULL
      AND assignment_id IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_work_offers_pending_order
  ON public.courier_work_offers (order_id)
  WHERE work_type = 'order' AND status = 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_work_offers_pending_package
  ON public.courier_work_offers (package_request_id)
  WHERE work_type = 'package' AND status = 'pending';

CREATE INDEX IF NOT EXISTS idx_courier_work_offers_courier_status
  ON public.courier_work_offers (courier_id, status, offered_at DESC);

ALTER TABLE public.courier_work_offers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.courier_work_offers FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.courier_work_offers TO service_role;

COMMENT ON TABLE public.courier_work_offers IS
  'Sipariş/Paket+ yönlendirmesinin hedef kuryeye özel, açık kabul bekleyen teklif kaydı. İstemci yalnız SECURITY DEFINER RPC''ler üzerinden erişir.';

-- Önceki sürümde devredilmiş ve ready durumunda kalmış siparişleri yeni teklif
-- modeline geçir. Normal kabul edilmiş siparişler on_the_way olduğu için girmez.
INSERT INTO public.courier_work_offers (
  work_type, order_id, assignment_id, courier_id, status, offered_at
)
SELECT
  'order', o.id, ca.id, ca.courier_id, 'pending', ca.assigned_at
FROM public.courier_assignments AS ca
JOIN public.orders AS o ON o.id = ca.order_id
WHERE ca.status = 'assigned'
  AND o.status = 'ready'
  AND NOT EXISTS (
    SELECT 1
    FROM public.courier_work_offers AS cwo
    WHERE cwo.order_id = o.id AND cwo.status = 'pending'
  )
ON CONFLICT DO NOTHING;

-- Canlıda notification ile yönlendirilmiş, henüz kabul edilmemiş Paket+ kayıtları
-- için son geçerli hedefi backfill et.
INSERT INTO public.courier_work_offers (
  work_type, package_request_id, courier_id, status, offered_at
)
SELECT DISTINCT ON (cr.id)
  'package', cr.id, n.user_id, 'pending', COALESCE(n.created_at, cr.created_at, now())
FROM public.courier_requests AS cr
JOIN public.notifications AS n
  ON n.entity_id = cr.id::text
 AND n.type IN ('package_route', 'new_package_request')
WHERE cr.status = 'pending'
  AND cr.courier_id IS NULL
  AND n.user_id <> cr.sender_id
  AND NOT EXISTS (
    SELECT 1
    FROM public.courier_request_rejections AS crr
    WHERE crr.request_id = cr.id AND crr.courier_id = n.user_id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.courier_work_offers AS cwo
    WHERE cwo.package_request_id = cr.id AND cwo.status = 'pending'
  )
ORDER BY cr.id, n.created_at DESC NULLS LAST, n.id DESC
ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------------------
-- Hedef kuryeye yönlendirilmiş sipariş teklifleri (PII yalnız hedefe açılır)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_courier_routed_order_offers(uuid);
DROP FUNCTION IF EXISTS public.get_courier_routed_order_offers();

CREATE FUNCTION public.get_courier_routed_order_offers()
RETURNS TABLE(
  offer_id uuid,
  assignment_id uuid,
  fee_amount numeric,
  order_id uuid,
  order_total numeric,
  order_status text,
  delivery_address_text text,
  customer_phone text,
  created_at timestamptz,
  shop_id uuid,
  shop_name text,
  order_items_json jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye rolü gerekli' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    cwo.id::uuid,
    ca.id::uuid,
    ca.fee_amount::numeric,
    o.id::uuid,
    o.total::numeric,
    o.status::text,
    o.delivery_address_text::text,
    o.customer_phone::text,
    o.created_at::timestamptz,
    o.shop_id::uuid,
    s.name::text,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'quantity', oi.quantity,
            'product_name', oi.product_name
          ) ORDER BY oi.product_name, oi.quantity
        )
        FROM public.order_items AS oi
        WHERE oi.order_id = o.id
      ),
      '[]'::jsonb
    )
  FROM public.courier_work_offers AS cwo
  JOIN public.courier_assignments AS ca
    ON ca.id = cwo.assignment_id
   AND ca.order_id = cwo.order_id
   AND ca.courier_id = cwo.courier_id
  JOIN public.orders AS o ON o.id = cwo.order_id
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE cwo.work_type = 'order'
    AND cwo.status = 'pending'
    AND cwo.courier_id = v_uid
    AND ca.status = 'assigned'
    AND o.status = 'ready'
  ORDER BY cwo.offered_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_routed_order_offers()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_routed_order_offers()
  TO authenticated;

-- Yönlendirilmiş sipariş ancak hedef kurye açıkça kabul edince aktif olur.
DROP FUNCTION IF EXISTS public.accept_routed_order_offer(uuid);

CREATE FUNCTION public.accept_routed_order_offer(p_offer_id uuid)
RETURNS TABLE(
  r_assignment_id uuid,
  r_order_id uuid,
  r_fee_amount numeric,
  r_order_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_offer public.courier_work_offers%ROWTYPE;
  v_assignment public.courier_assignments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_courier_name text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_offer_id IS NULL THEN
    RAISE EXCEPTION 'APP:offer_id_required' USING ERRCODE = '22023';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye rolü gerekli' USING ERRCODE = '42501';
  END IF;

  SELECT cwo.* INTO v_offer
  FROM public.courier_work_offers AS cwo
  WHERE cwo.id = p_offer_id
  FOR UPDATE;

  IF v_offer.id IS NULL OR v_offer.work_type <> 'order' THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_offer.courier_id <> v_uid THEN
    RAISE EXCEPTION 'APP:not_offer_owner' USING ERRCODE = '42501';
  END IF;
  IF v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'APP:offer_not_pending' USING ERRCODE = 'P0001';
  END IF;

  SELECT ca.* INTO v_assignment
  FROM public.courier_assignments AS ca
  WHERE ca.id = v_offer.assignment_id
  FOR UPDATE;

  SELECT o.* INTO v_order
  FROM public.orders AS o
  WHERE o.id = v_offer.order_id
  FOR UPDATE;

  IF v_assignment.id IS NULL
     OR v_assignment.order_id <> v_offer.order_id
     OR v_assignment.courier_id <> v_uid
     OR v_assignment.status <> 'assigned'
     OR v_order.id IS NULL
     OR v_order.status <> 'ready' THEN
    UPDATE public.courier_work_offers
    SET status = 'expired', responded_at = now()
    WHERE id = p_offer_id;
    RAISE EXCEPTION 'APP:offer_stale' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.courier_work_offers
  SET status = 'accepted', responded_at = now()
  WHERE id = p_offer_id;

  UPDATE public.orders
  SET status = 'on_the_way', updated_at = now()
  WHERE id = v_order.id;

  SELECT COALESCE(p.full_name, p.username, 'Kurye') INTO v_courier_name
  FROM public.profiles AS p
  WHERE p.id = v_uid;

  PERFORM public.add_notification(
    p_user_id => v_order.user_id,
    p_type => 'order_update',
    p_title => '🚴 Siparişiniz Yolda!',
    p_content => COALESCE(v_courier_name, 'Kurye') ||
      ' siparişinizi teslim etmek için yola çıktı.',
    p_entity_id => v_order.id::text
  );

  RETURN QUERY SELECT
    v_assignment.id,
    v_order.id,
    v_assignment.fee_amount::numeric,
    'on_the_way'::text;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_routed_order_offer(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_routed_order_offer(uuid)
  TO authenticated;

-- Kabul bekleyen yönlendirilmiş siparişleri "Siparişlerim"den çıkar.
DROP FUNCTION IF EXISTS public.get_courier_active_orders(uuid);
DROP FUNCTION IF EXISTS public.get_courier_active_orders();

CREATE FUNCTION public.get_courier_active_orders()
RETURNS TABLE(
  assignment_id uuid,
  assignment_status text,
  fee_amount numeric,
  assigned_at timestamptz,
  order_id uuid,
  order_total numeric,
  order_status text,
  delivery_address_text text,
  customer_phone text,
  created_at timestamptz,
  shop_name text,
  order_items_json jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_courier_role() AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye veya admin gerekli'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    ca.id::uuid,
    ca.status::text,
    ca.fee_amount::numeric,
    ca.assigned_at::timestamptz,
    o.id::uuid,
    o.total::numeric,
    o.status::text,
    o.delivery_address_text::text,
    o.customer_phone::text,
    o.created_at::timestamptz,
    s.name::text,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'quantity', oi.quantity,
            'product_name', oi.product_name
          ) ORDER BY oi.product_name, oi.quantity
        )
        FROM public.order_items AS oi
        WHERE oi.order_id = o.id
      ),
      '[]'::jsonb
    )
  FROM public.courier_assignments AS ca
  JOIN public.orders AS o ON o.id = ca.order_id
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE (ca.courier_id = v_uid OR public.is_admin())
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_work_offers AS cwo
      WHERE cwo.assignment_id = ca.id
        AND cwo.status = 'pending'
    )
  ORDER BY ca.assigned_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_active_orders()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_active_orders()
  TO authenticated;

-- ----------------------------------------------------------------------------
-- Paket+ Atanabilir listesi. Hedef kurye tam alım/teslim bilgisini görür.
-- Henüz hedeflenmemiş genel havuz kaydında PII yerine açık bir gizlilik özeti
-- döner; kartta alım/teslim artık boş görünmez.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.list_available_package_requests(uuid);
DROP FUNCTION IF EXISTS public.list_available_package_requests();

CREATE FUNCTION public.list_available_package_requests()
RETURNS TABLE(
  offer_id uuid,
  id uuid,
  distance_km numeric,
  total_fee numeric,
  courier_fee numeric,
  delivery_card_label text,
  created_at timestamptz,
  sender_name text,
  sender_phone text,
  recipient_name text,
  recipient_phone text,
  pickup_address text,
  pickup_lat double precision,
  pickup_lng double precision,
  delivery_address text,
  delivery_address_detail text,
  delivery_lat double precision,
  delivery_lng double precision,
  is_routed boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye rolü gerekli' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  -- Hedeflenmiş teklif: yalnız hedef kurye ve tam operasyon bilgisi.
  SELECT
    cwo.id::uuid,
    cr.id::uuid,
    cr.distance_km::numeric,
    cr.total_fee::numeric,
    cr.courier_fee::numeric,
    cr.delivery_card_label::text,
    cr.created_at::timestamptz,
    cr.sender_name::text,
    cr.sender_phone::text,
    cr.recipient_name::text,
    cr.recipient_phone::text,
    cr.pickup_address::text,
    cr.pickup_lat::double precision,
    cr.pickup_lng::double precision,
    cr.delivery_address::text,
    cr.delivery_address_detail::text,
    cr.delivery_lat::double precision,
    cr.delivery_lng::double precision,
    true::boolean
  FROM public.courier_work_offers AS cwo
  JOIN public.courier_requests AS cr ON cr.id = cwo.package_request_id
  WHERE cwo.work_type = 'package'
    AND cwo.status = 'pending'
    AND cwo.courier_id = v_uid
    AND cr.status = 'pending'
    AND cr.courier_id IS NULL
    AND cr.sender_id <> v_uid
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_request_rejections AS crr
      WHERE crr.request_id = cr.id AND crr.courier_id = v_uid
    )

  UNION ALL

  -- Yönlendirme yapılamamış genel havuz: kabul edilebilir ancak PII kapalı.
  SELECT
    NULL::uuid,
    cr.id::uuid,
    cr.distance_km::numeric,
    cr.total_fee::numeric,
    cr.courier_fee::numeric,
    cr.delivery_card_label::text,
    cr.created_at::timestamptz,
    'Gönderici bilgisi kabul sonrası açılır'::text,
    NULL::text,
    NULL::text,
    NULL::text,
    'Alım adresi kabul sonrası açılır'::text,
    NULL::double precision,
    NULL::double precision,
    COALESCE(
      NULLIF(cr.delivery_card_label, ''),
      'Teslim adresi kabul sonrası açılır'
    )::text,
    NULL::text,
    NULL::double precision,
    NULL::double precision,
    false::boolean
  FROM public.courier_requests AS cr
  WHERE cr.status = 'pending'
    AND cr.courier_id IS NULL
    AND cr.sender_id <> v_uid
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_work_offers AS cwo
      WHERE cwo.package_request_id = cr.id AND cwo.status = 'pending'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_request_rejections AS crr
      WHERE crr.request_id = cr.id AND crr.courier_id = v_uid
    )
  ORDER BY 7 ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.list_available_package_requests()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_available_package_requests()
  TO authenticated;

-- ----------------------------------------------------------------------------
-- Paket oluşturma sonrası ilk hedefleme
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.route_new_package_request(uuid);

CREATE FUNCTION public.route_new_package_request(p_request_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_rec public.courier_requests%ROWTYPE;
  v_courier_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT cr.* INTO v_rec
  FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id
  FOR UPDATE;

  IF v_rec.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_rec.sender_id <> v_uid THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF v_rec.status <> 'pending' OR v_rec.courier_id IS NOT NULL THEN
    RETURN 0;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.courier_work_offers AS cwo
    WHERE cwo.package_request_id = p_request_id
  ) THEN
    RETURN 0;
  END IF;

  SELECT p.id INTO v_courier_id
  FROM public.profiles AS p
  WHERE p.role::text = 'courier'
    AND COALESCE(p.is_online, false) = true
    AND p.id <> v_rec.sender_id
    AND NOT EXISTS (
      SELECT 1 FROM public.courier_request_rejections AS crr
      WHERE crr.request_id = p_request_id AND crr.courier_id = p.id
    )
  ORDER BY COALESCE(p.delivered_count, 0) ASC, p.id
  LIMIT 1;

  IF v_courier_id IS NULL THEN
    RETURN 0;
  END IF;

  INSERT INTO public.courier_work_offers (
    work_type, package_request_id, courier_id
  ) VALUES (
    'package', p_request_id, v_courier_id
  );

  PERFORM public.add_notification(
    p_user_id => v_courier_id,
    p_type => 'package_route',
    p_title => '📦 Yeni Paket Talebi',
    p_content => 'Bir paket talebi size yönlendirildi. Kurye panelinden inceleyebilirsiniz.',
    p_entity_id => p_request_id::text
  );

  RETURN 1;
END;
$$;

REVOKE ALL ON FUNCTION public.route_new_package_request(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.route_new_package_request(uuid)
  TO authenticated;

-- ----------------------------------------------------------------------------
-- Paket kabul/ret: pending hedef varsa yalnız o hedef işlem yapabilir.
-- ----------------------------------------------------------------------------
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
  v_offer public.courier_work_offers%ROWTYPE;
  v_total numeric(12, 2);
  v_fee numeric(12, 2);
  v_admin numeric(12, 2);
  v_accepted_at timestamptz := clock_timestamp();
  v_commission_percent numeric := 20;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
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
    RAISE EXCEPTION 'APP:already_taken | talep zaten alınmış' USING ERRCODE = 'P0001';
  END IF;
  IF v_rec.sender_id = v_uid THEN
    RAISE EXCEPTION 'APP:self_accept_forbidden' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.courier_request_rejections AS crr
    WHERE crr.request_id = p_request_id AND crr.courier_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:previously_rejected' USING ERRCODE = 'P0001';
  END IF;

  SELECT cwo.* INTO v_offer
  FROM public.courier_work_offers AS cwo
  WHERE cwo.package_request_id = p_request_id AND cwo.status = 'pending'
  FOR UPDATE;

  IF v_offer.id IS NOT NULL AND v_offer.courier_id <> v_uid THEN
    RAISE EXCEPTION 'APP:routed_to_another_courier' USING ERRCODE = 'P0001';
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

  UPDATE public.courier_requests
  SET status = 'accepted',
      courier_id = v_uid,
      courier_fee = v_fee,
      admin_commission = v_admin,
      accepted_at = v_accepted_at
  WHERE id = p_request_id;

  UPDATE public.courier_work_offers
  SET status = CASE WHEN courier_id = v_uid THEN 'accepted' ELSE 'expired' END,
      responded_at = now()
  WHERE package_request_id = p_request_id AND status = 'pending';

  PERFORM public.add_notification(
    p_user_id => v_rec.sender_id,
    p_type => 'courier_assigned',
    p_title => 'Kurye Atandı',
    p_content => 'Paket talebiniz bir kurye tarafından kabul edildi.',
    p_entity_id => p_request_id::text
  );

  RETURN QUERY SELECT
    p_request_id, 'accepted'::text, v_uid, v_fee, v_admin, v_accepted_at;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_package_request(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_package_request(uuid)
  TO authenticated;

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
  v_offer public.courier_work_offers%ROWTYPE;
  v_next_courier_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
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

  SELECT cwo.* INTO v_offer
  FROM public.courier_work_offers AS cwo
  WHERE cwo.package_request_id = p_request_id AND cwo.status = 'pending'
  FOR UPDATE;

  IF v_offer.id IS NOT NULL AND v_offer.courier_id <> v_uid THEN
    RAISE EXCEPTION 'APP:not_offer_owner' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.courier_request_rejections (request_id, courier_id)
  VALUES (p_request_id, v_uid)
  ON CONFLICT DO NOTHING;

  UPDATE public.courier_requests AS cr
  SET rejected_by = ARRAY(
    SELECT DISTINCT rejected_id
    FROM unnest(COALESCE(cr.rejected_by, ARRAY[]::uuid[]) || ARRAY[v_uid]) AS rejected_id
  )
  WHERE cr.id = p_request_id;

  IF v_offer.id IS NOT NULL THEN
    UPDATE public.courier_work_offers
    SET status = 'rejected', responded_at = now()
    WHERE id = v_offer.id;
  END IF;

  SELECT p.id INTO v_next_courier_id
  FROM public.profiles AS p
  WHERE p.role::text = 'courier'
    AND p.id <> v_rec.sender_id
    AND p.id <> v_uid
    AND NOT EXISTS (
      SELECT 1 FROM public.courier_request_rejections AS crr
      WHERE crr.request_id = p_request_id AND crr.courier_id = p.id
    )
  ORDER BY COALESCE(p.is_online, false) DESC,
           COALESCE(p.delivered_count, 0) ASC,
           p.id
  LIMIT 1;

  IF v_next_courier_id IS NOT NULL THEN
    INSERT INTO public.courier_work_offers (
      work_type, package_request_id, courier_id
    ) VALUES (
      'package', p_request_id, v_next_courier_id
    );

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

REVOKE ALL ON FUNCTION public.reject_package_request(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_package_request(uuid)
  TO authenticated;

-- ----------------------------------------------------------------------------
-- Sipariş reddi: assignment yeni hedefe geçirilir ama hedef kabul edene kadar
-- pending offer olduğu için Atanabilir'de kalır.
-- ----------------------------------------------------------------------------
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

  UPDATE public.courier_work_offers
  SET status = 'rejected', responded_at = now()
  WHERE assignment_id = p_assignment_id
    AND courier_id = v_uid
    AND status = 'pending';

  SELECT p.id INTO v_next_courier_id
  FROM public.profiles AS p
  WHERE p.role::text = 'courier'
    AND p.id <> v_uid
    AND NOT EXISTS (
      SELECT 1 FROM public.courier_order_rejections AS cor
      WHERE cor.order_id = v_assignment.order_id AND cor.courier_id = p.id
    )
  ORDER BY COALESCE(p.is_online, false) DESC,
           COALESCE(p.delivered_count, 0) ASC,
           p.id
  LIMIT 1;

  UPDATE public.orders
  SET status = CASE WHEN status = 'on_the_way' THEN 'ready' ELSE status END,
      updated_at = now()
  WHERE id = v_assignment.order_id;

  IF v_next_courier_id IS NULL THEN
    UPDATE public.courier_assignments
    SET status = 'cancelled'
    WHERE id = p_assignment_id;

    RETURN QUERY SELECT p_assignment_id, NULL::uuid, 'available'::text;
    RETURN;
  END IF;

  UPDATE public.courier_assignments
  SET courier_id = v_next_courier_id,
      status = 'assigned',
      assigned_at = now()
  WHERE id = p_assignment_id;

  INSERT INTO public.courier_work_offers (
    work_type, order_id, assignment_id, courier_id
  ) VALUES (
    'order', v_assignment.order_id, p_assignment_id, v_next_courier_id
  );

  PERFORM public.add_notification(
    p_user_id => v_next_courier_id,
    p_type => 'courier_order_assigned',
    p_title => 'Sipariş Teklifi Sana Yönlendirildi',
    p_content => 'Devredilen siparişi Atanabilir ekranından inceleyip kabul edebilirsiniz.',
    p_entity_id => v_assignment.order_id::text
  );

  RETURN QUERY SELECT p_assignment_id, v_next_courier_id, 'offered'::text;
END;
$$;

REVOKE ALL ON FUNCTION public.reject_order_assignment(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_order_assignment(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.reject_order_assignment(uuid) IS
  'Siparişi sıradaki kuryeye pending teklif olarak yönlendirir; açık kabul edilene kadar Atanabilir ekranında kalır.';

NOTIFY pgrst, 'reload schema';
