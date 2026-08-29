-- =============================================================================
-- Kurye evrak onayını sipariş/paket dağıtımına gerçekten bağlar
-- -----------------------------------------------------------------------------
-- courier_documents (20260828000001) yalnız admin panelinde görünen bir kayıt
-- olarak yaşıyordu: submit_courier_documents / admin_review_courier_document
-- durumu (pending/approved/rejected) günceller ama hiçbir sipariş/paket dağıtım
-- fonksiyonu bu durumu kontrol etmiyordu. is_courier_role() yalnız
-- profiles.role='courier' bakıyor; evrakı reddedilmiş ya da hiç gönderilmemiş
-- bir kurye, onaylanmış biriyle birebir aynı şekilde sipariş/paket
-- alabiliyordu — evrak onayı hiçbir şeyi fiilen engellemiyordu.
--
-- Bu migration public.is_courier_document_approved() yardımcı fonksiyonunu
-- ekler ve onu kurye işini fiilen üstlendiren/kişiye yönlendiren 8 fonksiyona
-- ekler:
--   - Kabul/üstlenme (net "forbidden" hatası fırlatır):
--       assign_order_to_courier, accept_routed_order_offer, accept_package_request
--   - Havuz görünürlüğü (sessizce dışlar; buton UI'da hiç görünmez):
--       get_available_orders_for_courier, list_available_package_requests
--   - Otomatik en-uygun-kurye seçimi (aday listesinden sessizce çıkarır):
--       assign_order_to_courier (satıcı/admin yolu), route_new_package_request,
--       reject_package_request, reject_order_assignment
--
-- Idempotent: CREATE OR REPLACE kullanılır (imza değişmiyor), mevcut
-- REVOKE/GRANT tekrar uygulanır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 0) Yardımcı: kuryenin evrak onayı 'approved' mi?
-- is_courier_role() ile aynı desen — yalnız iç kullanım için (diğer
-- SECURITY DEFINER fonksiyonlardan çağrılır), authenticated'a GRANT edilmez.
-- courier_documents tablosunun kendisi zaten yalnız sahibi/admin tarafından
-- okunabiliyor (RLS); bu fonksiyon o kısıtı bilerek atlar (SECURITY DEFINER)
-- ama yalnız boolean döndürür, satırı sızdırmaz.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_courier_document_approved(
  p_courier_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.courier_documents AS cd
    WHERE cd.courier_id = COALESCE(p_courier_id, (SELECT auth.uid()))
      AND cd.status = 'approved'
  );
$$;

REVOKE ALL ON FUNCTION public.is_courier_document_approved(uuid)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.is_courier_document_approved(uuid) IS
  'Kurye evrak onayı approved mi? Parametre verilmezse auth.uid() kontrol edilir. Yalnız iç kullanım (diğer SECURITY DEFINER fonksiyonlardan çağrılır); authenticated''a doğrudan açık değil.';

-- -----------------------------------------------------------------------------
-- 1) get_available_orders_for_courier: havuzu onaysız kuryeye göstermez
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_available_orders_for_courier();

CREATE FUNCTION public.get_available_orders_for_courier()
RETURNS TABLE(
  id uuid,
  total numeric,
  shop_id uuid,
  shop_name text,
  created_at timestamptz,
  item_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    o.id,
    o.total,
    o.shop_id,
    s.name,
    o.created_at,
    (
      SELECT count(*)
      FROM public.order_items AS oi
      WHERE oi.order_id = o.id
    ) AS item_count
  FROM public.orders AS o
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE o.status IN ('confirmed', 'preparing', 'ready')
    AND COALESCE(s.has_own_courier, false) = false
    AND (SELECT auth.uid()) IS NOT NULL
    AND public.is_courier_role()
    AND public.is_courier_document_approved()
    AND o.user_id IS DISTINCT FROM (SELECT auth.uid())
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_assignments AS ca
      WHERE ca.order_id = o.id
        AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_order_rejections AS cor
      WHERE cor.order_id = o.id
        AND cor.courier_id = (SELECT auth.uid())
    )
  ORDER BY o.created_at ASC;
$$;

REVOKE ALL ON FUNCTION public.get_available_orders_for_courier()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_available_orders_for_courier()
  TO authenticated;

COMMENT ON FUNCTION public.get_available_orders_for_courier() IS
  'Kurye için PII içermeyen sipariş havuzu. Kuryesi olmayan satıcı siparişlerini döndürür; aktif/teslim edilmiş ataması olan, kuryenin kendi verdiği, daha önce reddettiği veya evrak onayı olmayan kuryeye siparişleri dışlar.';

-- -----------------------------------------------------------------------------
-- 2) assign_order_to_courier: self-accept + otomatik seçim + elle atama —
--    hedefe (v_target) evrak onayı zorunlu, yol fark etmeksizin.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.assign_order_to_courier(uuid, uuid);

CREATE FUNCTION public.assign_order_to_courier(
  p_order_id uuid,
  p_courier_id uuid DEFAULT NULL
)
RETURNS TABLE(
  r_assignment_id uuid,
  r_courier_id uuid,
  r_courier_name text,
  r_fee_amount numeric,
  r_order_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid        CONSTANT uuid := (SELECT auth.uid());
  v_target     uuid;
  v_self_assign boolean := false;
  v_order      public.orders%ROWTYPE;
  v_assignment_id uuid;
  v_existing   uuid;
  v_fee        numeric(12, 2);
  v_courier_name text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'APP:order_id_required' USING ERRCODE = '22023';
  END IF;

  -- Siparişi kilitle (paralel atayan çağrıları serialize eder)
  SELECT o.* INTO v_order
  FROM public.orders AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- Hedef kurye + yetkilendirme
  IF p_courier_id IS NULL THEN
    IF public.is_courier_role() THEN
      v_target := v_uid;
      v_self_assign := true;
    ELSE
      -- satıcı/admin değilse reddet; satıcı yalnız kendi dükkanının siparişini atayabilir
      IF NOT public.is_admin() AND NOT EXISTS (
        SELECT 1 FROM public.shops AS s
        WHERE s.id = v_order.shop_id AND s.owner_id = v_uid
      ) THEN
        RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
      END IF;
      -- En uygun kurye: online優先, en az teslimat, reddetmeyen, evrakı onaylı
      SELECT p.id INTO v_target
      FROM public.profiles AS p
      WHERE p.role = 'courier'::public.user_role
        AND p.id IS DISTINCT FROM v_order.user_id
        AND public.is_courier_document_approved(p.id)
        AND NOT EXISTS (
          SELECT 1 FROM public.courier_order_rejections AS cor
          WHERE cor.order_id = p_order_id AND cor.courier_id = p.id
        )
      ORDER BY COALESCE(p.is_online, false) DESC,
               COALESCE(p.delivered_count, 0) ASC,
               p.id
      LIMIT 1;
      IF v_target IS NULL THEN
        RAISE EXCEPTION 'APP:no_courier_available' USING ERRCODE = 'P0001';
      END IF;
    END IF;
  ELSE
    v_target := p_courier_id;
    IF NOT public.is_admin() AND NOT EXISTS (
      SELECT 1 FROM public.shops AS s
      WHERE s.id = v_order.shop_id AND s.owner_id = v_uid
    ) THEN
      RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Evrak onayı olmayan kurye siparişi teslim alamaz — self-accept, otomatik
  -- seçim (yukarıda zaten filtrelendi, burada savunma amaçlı tekrar kontrol)
  -- veya admin/satıcının elle p_courier_id vermesi fark etmeksizin.
  IF NOT public.is_courier_document_approved(v_target) THEN
    RAISE EXCEPTION 'APP:courier_documents_not_approved' USING ERRCODE = '42501';
  END IF;

  -- Zaten aktif atama var mı (anti-race; order FOR UPDATE ile serialize edildi)
  SELECT ca.id INTO v_existing
  FROM public.courier_assignments AS ca
  WHERE ca.order_id = p_order_id
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
  LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'APP:already_assigned' USING ERRCODE = 'P0001';
  END IF;

  -- Ücret: courier_settings.fee_per_delivery (yoksa 15)
  SELECT cs.fee_per_delivery INTO v_fee
  FROM public.courier_settings AS cs
  LIMIT 1;
  v_fee := COALESCE(v_fee, 15);

  INSERT INTO public.courier_assignments (
    order_id, courier_id, status, fee_amount, assigned_at
  ) VALUES (
    p_order_id, v_target, 'assigned', v_fee, now()
  )
  RETURNING id INTO v_assignment_id;

  -- Müşteriye "yolda" görünsün (mevcut _acceptOrder davranışını korur)
  UPDATE public.orders
     SET status = 'on_the_way', updated_at = now()
   WHERE id = p_order_id
     AND status IN ('confirmed', 'preparing', 'ready');

  SELECT COALESCE(p.full_name, p.username, 'Kurye') INTO v_courier_name
  FROM public.profiles AS p
  WHERE p.id = v_target;

  -- Müşteriye tek "yolda" bildirimi (önceden hem accept hem pickup'ta çift gidiyordu)
  PERFORM public.add_notification(
    p_user_id  => v_order.user_id,
    p_type     => 'order_update',
    p_title    => '🚴 Siparişiniz Yolda!',
    p_content  => v_courier_name || ' siparişinizi teslim etmek için yola çıktı.',
    p_entity_id => p_order_id::text
  );

  -- Atanan kuryeye bildirim (otomatik/satıcı yolu); self-accept'te atlanır
  IF NOT v_self_assign THEN
    PERFORM public.add_notification(
      p_user_id   => v_target,
      p_type      => 'courier_order_assigned',
      p_title     => '🛵 Sipariş Sana Atandı!',
      p_content   => 'Sana bir sipariş atandı. Kurye panelinden teslim alabilirsin.',
      p_entity_id => p_order_id::text
    );
  END IF;

  RETURN QUERY
  SELECT v_assignment_id, v_target, v_courier_name, v_fee, 'on_the_way'::text;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_order_to_courier(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_order_to_courier(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.assign_order_to_courier(uuid, uuid) IS
  'Siparişi atomik olarak kuryeye atar (self-accept / auto-select / seller). FOR UPDATE ile TOCTOU koruması; orders.status=on_the_way; müşteriye tek "yolda" bildirimi. Hedef kuryenin evrak onayı approved olmalı. İstemci doğrudan courier_assignments INSERT edemez (RLS INSERT policy yok).';

-- -----------------------------------------------------------------------------
-- 3) accept_routed_order_offer: yönlendirilmiş sipariş teklifini kabul
-- -----------------------------------------------------------------------------
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
  IF NOT public.is_courier_document_approved(v_uid) THEN
    RAISE EXCEPTION 'APP:courier_documents_not_approved' USING ERRCODE = '42501';
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

-- -----------------------------------------------------------------------------
-- 4) accept_package_request: Paket+ talebini kabul
-- -----------------------------------------------------------------------------
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
  IF NOT public.is_courier_document_approved(v_uid) THEN
    RAISE EXCEPTION 'APP:courier_documents_not_approved' USING ERRCODE = '42501';
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

-- -----------------------------------------------------------------------------
-- 5) list_available_package_requests: havuzu onaysız kuryeye göstermez
-- -----------------------------------------------------------------------------
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
  -- Havuzu sessizce boş döndür (hata değil) — Flutter tarafı evrak durumunu
  -- ayrıca courier_documents'tan okuyup bilgilendirici bir banner gösterir.
  IF NOT public.is_courier_document_approved(v_uid) THEN
    RETURN;
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

-- -----------------------------------------------------------------------------
-- 6) route_new_package_request: yalnız evrakı onaylı, online kuryeye yönlendir
-- -----------------------------------------------------------------------------
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
    AND public.is_courier_document_approved(p.id)
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

-- -----------------------------------------------------------------------------
-- 7) reject_package_request: ret sonrası yeniden yönlendirme de onaylı hedefe
-- -----------------------------------------------------------------------------
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
    AND public.is_courier_document_approved(p.id)
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

-- -----------------------------------------------------------------------------
-- 8) reject_order_assignment: ret sonrası devir de onaylı hedefe
-- -----------------------------------------------------------------------------
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
    AND public.is_courier_document_approved(p.id)
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
  'Siparişi sıradaki (evrakı onaylı) kuryeye pending teklif olarak yönlendirir; açık kabul edilene kadar Atanabilir ekranında kalır.';

NOTIFY pgrst, 'reload schema';
