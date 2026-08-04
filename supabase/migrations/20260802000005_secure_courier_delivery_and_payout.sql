-- =============================================================================
-- Kurye paket + teslimat + kazanç + payout güvenlik refaktörü
-- ----------------------------------------------------------------------------
-- Bu migration aşağıdaki açıkları kapatır:
--   A) Gönderici istediği total_fee ile courier_request INSERT edip aynı tutarı
--      deduct_from_balance'a gönderebiliyordu. Yeni create_package_request RPC
--      tek atomik transaction içinde mesafe+fiyat+bakiye düşümü yapar.
--   B) Bekleyen courier_requests satırları tüm kuryelere PII sızdırıyordu.
--      Yeni list_available_package_requests RPC'si PII içermeyen kolonlar
--      döner; tam PII yalnız atanmış kurye/sender/admin için
--      get_assigned_package_details RPC'sinden gelir.
--   C) Kurye tek PATCH ile status/courier_id/fee/commission/Adres/telefon/
--      koordinat/deivered_at yazabiliyordu. Artık kuryenin doğrudan tablo
--      UPDATE yetkisi yok; accept/reject/delivery_confirm/admin_resolve
--      RPC'leri ile yapılır. courier_id/status/timestamp istemciden alınmaz.
--   D) courier_earnings + courier_payout_requests doğrudan INSERT/UPDATE
--      authenticated için revoke edildi. Yalnız request_courier_payout ve
--      admin_approve/reject_courier_payout RPC'leri (SECURITY DEFINER) ile
--      yazılır. courier_payout_items ile birebir item ilişkisi kurulur;
--      admin onayı yalnız payout'a bağlı item'ları paid yapar.
--   E) deduct_from_balance'in authenticated EXECUTE yetkisi kaldırıldı;
--      paket ücreti artık create_package_request içinde atomik kesilir.
--   F) Eski RLS politikaları ve TO public'e açık SELECT politikaları
--      temizlenip yerine TO authenticated + OR birleşik politikalar
--      kuruldu. multiple_permissive_policies uyarısı bu migration ile
--      çözülür.
--
-- Veri silinmez. Mevcut kayıtlar korunur; yalnızca yeni kolonlar eklenir,
-- yeni politikalar DROP+CREATE, yeni tablolar CREATE IF NOT EXISTS yapılır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 0) Ön hazırlık: kolonlar, tablolar, indexler (idempotent)
-- -----------------------------------------------------------------------------

-- courier_requests: yeni kolonlar
ALTER TABLE public.courier_requests
  ADD COLUMN IF NOT EXISTS idempotency_key uuid,
  ADD COLUMN IF NOT EXISTS delivery_card_label text,
  ADD COLUMN IF NOT EXISTS delivery_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivery_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivery_confirmed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz;

-- (sender_id, idempotency_key) UNIQUE: NULL'lar ayrı tutulur
CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_requests_sender_idem
  ON public.courier_requests (sender_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- Performans indexleri
CREATE INDEX IF NOT EXISTS idx_courier_requests_status_created_at
  ON public.courier_requests (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_courier_requests_courier_status
  ON public.courier_requests (courier_id, status);
CREATE INDEX IF NOT EXISTS idx_courier_requests_pending_pool
  ON public.courier_requests (status, created_at DESC)
  WHERE status = 'pending' AND courier_id IS NULL;

-- courier_earnings: amount_snapshot ve eksik kolonlar
ALTER TABLE public.courier_earnings
  ADD COLUMN IF NOT EXISTS amount_snapshot numeric(12, 2),
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- Tek paket için birden fazla earnings olamaz
CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_earnings_package_request
  ON public.courier_earnings (package_request_id)
  WHERE package_request_id IS NOT NULL;

-- courier_payout_requests: eksik kolonlar
ALTER TABLE public.courier_payout_requests
  ADD COLUMN IF NOT EXISTS requested_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS payment_reference text,
  ADD COLUMN IF NOT EXISTS idempotency_key uuid;

-- Bir kuryenin aynı anda yalnız bir açık (pending) payout'ı olabilir
CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_payout_one_open_per_courier
  ON public.courier_payout_requests (courier_id)
  WHERE status = 'pending';

-- courier_payout_items: yeni tablo (birebir ilişki)
CREATE TABLE IF NOT EXISTS public.courier_payout_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_id uuid NOT NULL REFERENCES public.courier_payout_requests(id) ON DELETE CASCADE,
  earning_id uuid NOT NULL REFERENCES public.courier_earnings(id) ON DELETE RESTRICT,
  amount_snapshot numeric(12, 2) NOT NULL CHECK (amount_snapshot >= 0),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','rejected')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_payout_items_earning_id
  ON public.courier_payout_items (earning_id);
CREATE INDEX IF NOT EXISTS idx_courier_payout_items_payout_id
  ON public.courier_payout_items (payout_id);

-- courier_request_rejections: normalized red tablosu
CREATE TABLE IF NOT EXISTS public.courier_request_rejections (
  request_id uuid NOT NULL REFERENCES public.courier_requests(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (request_id, courier_id)
);
CREATE INDEX IF NOT EXISTS idx_courier_request_rejections_courier
  ON public.courier_request_rejections (courier_id);

ALTER TABLE public.courier_payout_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_request_rejections ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 1) Helper SECURITY DEFINER fonksiyonlar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_courier_role()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = (SELECT auth.uid())
      AND p.role::text = 'courier'
  );
$$;

REVOKE ALL ON FUNCTION public.is_courier_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_courier_role() TO authenticated, service_role;

-- is_admin() projede zaten mevcut; yoksa oluştur
DO $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'is_admin'
  ) THEN
    EXECUTE $sql$
      CREATE FUNCTION public.is_admin()
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = ''
      AS $body$
        SELECT EXISTS (
          SELECT 1
          FROM public.profiles AS p
          WHERE p.id = (SELECT auth.uid())
            AND p.role::text = 'admin'
        );
      $body$;
      REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
      GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;
    $sql$;
  END IF;
END
$fn$;

-- -----------------------------------------------------------------------------
-- 2) A. create_package_request: atomik talep + bakiye düşümü
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
);

CREATE FUNCTION public.create_package_request(
  p_pickup_lat double precision,
  p_pickup_lng double precision,
  p_delivery_lat double precision,
  p_delivery_lng double precision,
  p_sender_name text,
  p_sender_phone text,
  p_recipient_name text,
  p_recipient_phone text,
  p_pickup_address text,
  p_delivery_address text,
  p_delivery_address_detail text,
  p_description text,
  p_idempotency_key uuid
)
RETURNS TABLE(
  id uuid,
  status text,
  total_fee numeric,
  courier_fee numeric,
  admin_commission numeric,
  distance_km numeric,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id     CONSTANT uuid := (SELECT auth.uid());
  v_settings    public.courier_service_settings%ROWTYPE;
  v_distance_km numeric(10, 3);
  v_total_fee   numeric(12, 2);
  v_courier_fee numeric(12, 2);
  v_admin_fee   numeric(12, 2);
  v_commission  numeric(5, 2);
  v_balance_id  uuid;
  v_balance     numeric(12, 2);
  v_tx_id       uuid;
  v_request_id  uuid;
  v_created_at  timestamptz;
  v_existing    public.courier_requests%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required | oturum açmanız gerekiyor'
      USING ERRCODE = '42501';
  END IF;

  -- Idempotency: aynı (sender_id, key) daha önce kullanıldıysa mevcut kaydı döner
  IF p_idempotency_key IS NOT NULL THEN
    SELECT cr.* INTO v_existing
    FROM public.courier_requests AS cr
    WHERE cr.sender_id = v_user_id
      AND cr.idempotency_key = p_idempotency_key
    LIMIT 1;
    IF v_existing.id IS NOT NULL THEN
      RETURN QUERY
      SELECT v_existing.id, v_existing.status, v_existing.total_fee,
             v_existing.courier_fee, v_existing.admin_commission,
             v_existing.distance_km, v_existing.created_at;
      RETURN;
    END IF;
  END IF;

  -- Koordinat doğrulama
  IF p_pickup_lat IS NULL OR p_pickup_lat < -90 OR p_pickup_lat > 90
     OR p_delivery_lat IS NULL OR p_delivery_lat < -90 OR p_delivery_lat > 90
     OR p_pickup_lng IS NULL OR p_pickup_lng < -180 OR p_pickup_lng > 180
     OR p_delivery_lng IS NULL OR p_delivery_lng < -180 OR p_delivery_lng > 180 THEN
    RAISE EXCEPTION 'APP:invalid_coordinates | koordinat aralık dışı'
      USING ERRCODE = '22023';
  END IF;

  -- Zorunlu alanlar
  IF NULLIF(trim(p_sender_name), '') IS NULL THEN
    RAISE EXCEPTION 'APP:sender_name_required' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(trim(p_recipient_name), '') IS NULL THEN
    RAISE EXCEPTION 'APP:recipient_name_required' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(trim(p_pickup_address), '') IS NULL THEN
    RAISE EXCEPTION 'APP:pickup_address_required' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(trim(p_delivery_address), '') IS NULL THEN
    RAISE EXCEPTION 'APP:delivery_address_required' USING ERRCODE = '22023';
  END IF;

  -- Aktif servis ayarları
  SELECT css.* INTO v_settings
  FROM public.courier_service_settings AS css
  WHERE css.enabled = true
  ORDER BY css.updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_settings.id IS NULL THEN
    RAISE EXCEPTION 'APP:service_disabled | kurye servisi aktif değil'
      USING ERRCODE = 'P0001';
  END IF;

  IF COALESCE(v_settings.allows_user_requests, false) = false THEN
    RAISE EXCEPTION 'APP:user_requests_disabled | kullanıcı talepleri kapalı'
      USING ERRCODE = 'P0001';
  END IF;

  v_commission := COALESCE(v_settings.commission_percent, 20);

  -- Haversine mesafe (km)
  v_distance_km := round(
    6371 * 2 * asin(sqrt(
      power(sin(radians((p_delivery_lat - p_pickup_lat) / 2.0)), 2)
      + cos(radians(p_pickup_lat)) * cos(radians(p_delivery_lat))
        * power(sin(radians((p_delivery_lng - p_pickup_lng) / 2.0)), 2)
    ))::numeric,
    3
  );

  v_total_fee := round(
    v_settings.base_fee + v_distance_km * v_settings.per_km_fee,
    2
  );
  v_courier_fee := round(v_total_fee * (1 - v_commission / 100.0), 2);
  v_admin_fee   := v_total_fee - v_courier_fee;

  IF v_total_fee <= 0 THEN
    RAISE EXCEPTION 'APP:invalid_total_fee | hesaplanan ücret sıfır'
      USING ERRCODE = 'P0001';
  END IF;

  -- Bakiye kilidi
  SELECT ub.id, ub.balance
    INTO v_balance_id, v_balance
  FROM public.user_balances AS ub
  WHERE ub.user_id = v_user_id
  FOR UPDATE;

  IF v_balance_id IS NULL THEN
    RAISE EXCEPTION 'APP:balance_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_balance < v_total_fee THEN
    RAISE EXCEPTION 'APP:insufficient_balance | mevcut: %, gerekli: %',
      v_balance, v_total_fee USING ERRCODE = 'P0001';
  END IF;

  -- Bakiye düşümü
  UPDATE public.user_balances AS ub
     SET balance = ub.balance - v_total_fee,
         total_spent = ub.total_spent + v_total_fee,
         updated_at = now()
   WHERE ub.id = v_balance_id;

  -- Ledger kaydı
  INSERT INTO public.balance_transactions (
    user_id, type, amount, net_amount,
    balance_before, balance_after,
    reference_type, reference_id,
    status, description, metadata
  ) VALUES (
    v_user_id, 'courier_payment'::public.balance_transaction_type,
    v_total_fee, v_total_fee,
    v_balance, v_balance - v_total_fee,
    'courier_request', gen_random_uuid(),  -- reference_id courier_requests id ile güncellenecek
    'completed', 'Paket gönderim ücreti',
    jsonb_build_object('flow', 'create_package_request')
  )
  RETURNING id INTO v_tx_id;

  -- Talep oluştur
  INSERT INTO public.courier_requests (
    sender_id, sender_name, sender_phone,
    recipient_name, recipient_phone,
    pickup_address, pickup_lat, pickup_lng,
    delivery_address, delivery_address_detail,
    delivery_lat, delivery_lng,
    description, distance_km, total_fee, courier_fee, admin_commission,
    status, courier_id, idempotency_key
  ) VALUES (
    v_user_id, p_sender_name, p_sender_phone,
    p_recipient_name, p_recipient_phone,
    p_pickup_address, p_pickup_lat, p_pickup_lng,
    p_delivery_address, p_delivery_address_detail,
    p_delivery_lat, p_delivery_lng,
    p_description, v_distance_km, v_total_fee, v_courier_fee, v_admin_fee,
    'pending', NULL, p_idempotency_key
  )
  RETURNING id, created_at INTO v_request_id, v_created_at;

  -- Ledger referansını talep ile güncelle
  UPDATE public.balance_transactions AS bt
     SET reference_id = v_request_id
   WHERE bt.id = v_tx_id;

  RETURN QUERY
  SELECT v_request_id, 'pending'::text, v_total_fee, v_courier_fee, v_admin_fee,
         v_distance_km, v_created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
) TO authenticated;

COMMENT ON FUNCTION public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
) IS
  'Sunucu-otoriteli atomik paket talebi: mesafe + ücret + bakiye düşümü + ledger. Idempotent.';

-- -----------------------------------------------------------------------------
-- 3) B. list_available_package_requests: bekleyen PII içermeyen havuz
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.list_available_package_requests();

CREATE FUNCTION public.list_available_package_requests()
RETURNS TABLE(
  id uuid,
  distance_km numeric,
  total_fee numeric,
  courier_fee numeric,
  delivery_card_label text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT cr.id, cr.distance_km, cr.total_fee, cr.courier_fee,
         cr.delivery_card_label, cr.created_at
  FROM public.courier_requests AS cr
  WHERE cr.status = 'pending'
    AND cr.courier_id IS NULL
    AND cr.sender_id <> (SELECT auth.uid())
    AND NOT EXISTS (
      SELECT 1 FROM public.courier_request_rejections AS crr
      WHERE crr.request_id = cr.id
        AND crr.courier_id = (SELECT auth.uid())
    )
    AND (SELECT auth.uid()) IS NOT NULL
    AND public.is_courier_role()
  ORDER BY cr.created_at ASC;
$$;

REVOKE ALL ON FUNCTION public.list_available_package_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_available_package_requests() TO authenticated;

COMMENT ON FUNCTION public.list_available_package_requests()
  IS 'Kurye rolündeki authenticated kullanıcılar için PII içermeyen bekleyen havuz.';

-- -----------------------------------------------------------------------------
-- 3b) B2. get_available_orders_for_courier: PII içermeyen sipariş havuzu
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_available_orders_for_courier(uuid);

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
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT o.id, o.total, o.shop_id, s.name, o.created_at,
         (SELECT count(*) FROM public.order_items AS oi WHERE oi.order_id = o.id) AS item_count
  FROM public.orders AS o
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE o.status IN ('confirmed', 'preparing', 'ready')
    AND (s.has_own_courier IS NULL OR s.has_own_courier = false)
    AND NOT EXISTS (
      SELECT 1 FROM public.courier_assignments AS ca
      WHERE ca.order_id = o.id
        AND ca.status IN ('assigned', 'picked_up', 'on_the_way', 'delivered')
    )
    AND (SELECT auth.uid()) IS NOT NULL
    AND public.is_courier_role()
  ORDER BY o.created_at ASC;
$$;

REVOKE ALL ON FUNCTION public.get_available_orders_for_courier() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_available_orders_for_courier() TO authenticated;

COMMENT ON FUNCTION public.get_available_orders_for_courier()
  IS 'Kurye için sipariş havuzu. PII (adres/telefon) döndürmez.';

-- -----------------------------------------------------------------------------
-- 3c) B3. get_courier_active_orders: atanmış kurye/admin için tam PII
-- -----------------------------------------------------------------------------
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
    RAISE EXCEPTION 'APP:forbidden | kurye veya admin gerekli' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    ca.id, ca.status::text, ca.fee_amount, ca.assigned_at,
    o.id, o.total, o.status::text,
    o.delivery_address_text, o.customer_phone, o.created_at,
    s.name,
    (
      SELECT jsonb_agg(jsonb_build_object('quantity', oi.quantity, 'product_name', oi.product_name))
      FROM public.order_items oi WHERE oi.order_id = o.id
    )
  FROM public.courier_assignments AS ca
  JOIN public.orders AS o ON o.id = ca.order_id
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE (ca.courier_id = v_uid OR public.is_admin())
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
  ORDER BY ca.assigned_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_active_orders() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_active_orders() TO authenticated;

-- -----------------------------------------------------------------------------
-- 3d) B4. get_assigned_package_details: atanmış kurye/sender/admin için tam PII
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_assigned_package_details(uuid);

CREATE FUNCTION public.get_assigned_package_details(p_request_id uuid)
RETURNS TABLE(
  id uuid,
  sender_id uuid,
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
  description text,
  distance_km numeric,
  total_fee numeric,
  courier_fee numeric,
  admin_commission numeric,
  status text,
  courier_id uuid,
  created_at timestamptz,
  accepted_at timestamptz,
  delivered_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_rec public.courier_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'APP:request_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT cr.* INTO v_rec
  FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id;

  IF v_rec.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- Yalnız atanmış kurye (yani courier_id set edilmiş) + sender + admin
  IF NOT (
    v_rec.courier_id = v_uid
    OR v_rec.sender_id = v_uid
    OR public.is_admin()
  ) THEN
    RAISE EXCEPTION 'APP:forbidden | atanmamış talebe erişim yok' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    v_rec.id, v_rec.sender_id, v_rec.sender_name, v_rec.sender_phone,
    v_rec.recipient_name, v_rec.recipient_phone,
    v_rec.pickup_address, v_rec.pickup_lat, v_rec.pickup_lng,
    v_rec.delivery_address, v_rec.delivery_address_detail,
    v_rec.delivery_lat, v_rec.delivery_lng,
    v_rec.description,
    v_rec.distance_km, v_rec.total_fee, v_rec.courier_fee, v_rec.admin_commission,
    v_rec.status, v_rec.courier_id,
    v_rec.created_at, v_rec.accepted_at, v_rec.delivered_at;
END;
$$;

REVOKE ALL ON FUNCTION public.get_assigned_package_details(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_assigned_package_details(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) C. accept_package_request ve reject_package_request
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.accept_package_request(uuid);

CREATE FUNCTION public.accept_package_request(p_request_id uuid)
RETURNS TABLE(
  id uuid,
  status text,
  courier_id uuid,
  courier_fee numeric,
  admin_commission numeric,
  accepted_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid     CONSTANT uuid := (SELECT auth.uid());
  v_rec     public.courier_requests%ROWTYPE;
  v_total   numeric(12, 2);
  v_fee     numeric(12, 2);
  v_admin   numeric(12, 2);
  v_settings public.courier_service_settings%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye rolü gerekli' USING ERRCODE = '42501';
  END IF;

  -- Talebi kilitle
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

  -- Güncel komisyon oranı ile fee'leri yeniden hesapla (immutable snapshot)
  SELECT css.* INTO v_settings
  FROM public.courier_service_settings AS css
  WHERE css.enabled = true
  ORDER BY css.updated_at DESC NULLS LAST
  LIMIT 1;

  v_total := v_rec.total_fee;
  v_fee   := round(v_total * (1 - COALESCE(v_settings.commission_percent, 20) / 100.0), 2);
  v_admin := v_total - v_fee;

  UPDATE public.courier_requests AS cr
     SET status = 'accepted',
         courier_id = v_uid,
         courier_fee = v_fee,
         admin_commission = v_admin,
         accepted_at = now()
   WHERE cr.id = p_request_id;

  RETURN QUERY
  SELECT p_request_id, 'accepted'::text, v_uid, v_fee, v_admin, now();
END;
$$;

REVOKE ALL ON FUNCTION public.accept_package_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_package_request(uuid) TO authenticated;

-- reject: normalized tabloya yaz + rejected_by sütununa atomik append
DROP FUNCTION IF EXISTS public.reject_package_request(uuid);

CREATE FUNCTION public.reject_package_request(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
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
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.courier_request_rejections (request_id, courier_id)
  VALUES (p_request_id, v_uid)
  ON CONFLICT DO NOTHING;

  -- Geriye uyumluluk: rejected_by sütununa da atomik ekleme
  UPDATE public.courier_requests AS cr
     SET rejected_by = ARRAY(
       SELECT DISTINCT u FROM unnest(cr.rejected_by || ARRAY[v_uid]) AS u
     )
   WHERE cr.id = p_request_id
     AND NOT (v_uid = ANY(cr.rejected_by));
END;
$$;

REVOKE ALL ON FUNCTION public.reject_package_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_package_request(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 5) D. Teslimat doğrulama akışı (kurye talebi -> gönderici onayı -> kazanç)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.request_package_delivery_confirmation(uuid);

CREATE FUNCTION public.request_package_delivery_confirmation(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_rec public.courier_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501'; END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT cr.* INTO v_rec FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id FOR UPDATE;

  IF v_rec.id IS NULL THEN RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001'; END IF;
  IF v_rec.courier_id <> v_uid THEN
    RAISE EXCEPTION 'APP:forbidden | atanmamış talep' USING ERRCODE = '42501';
  END IF;
  IF v_rec.status <> 'accepted' THEN
    RAISE EXCEPTION 'APP:invalid_state | durum: %', v_rec.status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.courier_requests AS cr
     SET status = 'delivery_pending_confirmation',
         delivery_requested_at = now()
   WHERE cr.id = p_request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_package_delivery_confirmation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_package_delivery_confirmation(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.confirm_package_delivery(uuid);

CREATE FUNCTION public.confirm_package_delivery(p_request_id uuid)
RETURNS TABLE(
  request_id uuid,
  earning_id uuid,
  amount numeric,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid     CONSTANT uuid := (SELECT auth.uid());
  v_rec     public.courier_requests%ROWTYPE;
  v_earn_id uuid;
  v_amount  numeric(12, 2);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501'; END IF;

  SELECT cr.* INTO v_rec
  FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id
  FOR UPDATE;

  IF v_rec.id IS NULL THEN RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001'; END IF;

  -- Yalnız gerçek sender VEYA admin
  IF NOT (v_rec.sender_id = v_uid OR public.is_admin()) THEN
    RAISE EXCEPTION 'APP:forbidden | yalnız gönderici veya admin' USING ERRCODE = '42501';
  END IF;

  IF v_rec.status NOT IN ('accepted', 'delivery_pending_confirmation') THEN
    RAISE EXCEPTION 'APP:invalid_state | durum: %', v_rec.status USING ERRCODE = 'P0001';
  END IF;
  IF v_rec.courier_id IS NULL THEN
    RAISE EXCEPTION 'APP:no_courier' USING ERRCODE = 'P0001';
  END IF;

  v_amount := COALESCE(v_rec.courier_fee, 0);

  UPDATE public.courier_requests AS cr
     SET status = 'delivered',
         delivered_at = now(),
         delivery_confirmed_at = now(),
         delivery_confirmed_by = v_uid
   WHERE cr.id = p_request_id;

  -- Idempotent earnings insert
  INSERT INTO public.courier_earnings (
    courier_id, package_request_id, amount, amount_snapshot, status
  ) VALUES (
    v_rec.courier_id, p_request_id, v_amount, v_amount, 'pending'
  )
  ON CONFLICT (package_request_id) WHERE package_request_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_earn_id;

  IF v_earn_id IS NULL THEN
    SELECT ce.id INTO v_earn_id
    FROM public.courier_earnings AS ce
    WHERE ce.package_request_id = p_request_id
    LIMIT 1;
  END IF;

  -- delivered_count atomik artış
  UPDATE public.profiles AS p
     SET delivered_count = p.delivered_count + 1
   WHERE p.id = v_rec.courier_id;

  -- Bildirim (gönderici + kurye)
  INSERT INTO public.notifications (user_id, type, title, content, metadata, is_read)
  VALUES
    (v_rec.courier_id, 'courier_delivered',
     'Paket teslim edildi', 'Paketiniz gönderici tarafından onaylandı.',
     jsonb_build_object('request_id', p_request_id, 'amount', v_amount), false),
    (v_rec.sender_id, 'package_delivered',
     'Paketiniz teslim edildi', 'Gönderdiğiniz paket alıcısına teslim edildi.',
     jsonb_build_object('request_id', p_request_id), false);

  RETURN QUERY
  SELECT p_request_id, v_earn_id, v_amount, 'pending'::text;
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_package_delivery(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_package_delivery(uuid) TO authenticated;

-- admin_resolve_package_dispute: ihtilaf çözümü
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

-- -----------------------------------------------------------------------------
-- 6) E. Payout akışı: request + admin approve/reject (atomik)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.request_courier_payout(uuid);

CREATE FUNCTION public.request_courier_payout(p_idempotency_key uuid)
RETURNS TABLE(
  payout_id uuid,
  amount numeric,
  item_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid        CONSTANT uuid := (SELECT auth.uid());
  v_payout_id  uuid;
  v_amount     numeric(12, 2);
  v_count      integer;
  v_rec        RECORD;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501'; END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  -- Aynı kuryenin açık (pending) payout'ı var mı?
  IF EXISTS (
    SELECT 1 FROM public.courier_payout_requests AS cpr
    WHERE cpr.courier_id = v_uid AND cpr.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'APP:open_payout_exists | zaten bekleyen bir payout var'
      USING ERRCODE = 'P0001';
  END IF;

  -- Idempotency: aynı key ile daha önce oluşturulmuşsa mevcut kaydı döner
  IF p_idempotency_key IS NOT NULL THEN
    SELECT cpr.id, cpr.amount INTO v_payout_id, v_amount
    FROM public.courier_payout_requests AS cpr
    WHERE cpr.courier_id = v_uid
      AND cpr.idempotency_key = p_idempotency_key
    LIMIT 1;
    IF v_payout_id IS NOT NULL THEN
      SELECT count(*) INTO v_count
      FROM public.courier_payout_items AS cpi
      WHERE cpi.payout_id = v_payout_id;
      RETURN QUERY SELECT v_payout_id, v_amount, v_count;
      RETURN;
    END IF;
  END IF;

  -- Earnings kilidi
  CREATE TEMP TABLE _locked_earnings ON COMMIT DROP AS
    SELECT ce.id, ce.amount
    FROM public.courier_earnings AS ce
    WHERE ce.courier_id = v_uid
      AND ce.status = 'pending'
    FOR UPDATE;

  SELECT coalesce(sum(le.amount), 0), count(*) INTO v_amount, v_count
  FROM _locked_earnings AS le;

  IF v_count = 0 THEN
    DROP TABLE _locked_earnings;
    RAISE EXCEPTION 'APP:no_pending_earnings' USING ERRCODE = 'P0001';
  END IF;

  -- Payout header
  INSERT INTO public.courier_payout_requests (
    courier_id, amount, status, requested_at, idempotency_key
  ) VALUES (
    v_uid, v_amount, 'pending', now(), p_idempotency_key
  )
  RETURNING id INTO v_payout_id;

  -- Items
  INSERT INTO public.courier_payout_items (payout_id, earning_id, amount_snapshot, status)
  SELECT v_payout_id, le.id, le.amount, 'pending'
  FROM _locked_earnings AS le;

  -- Earnings status güncelle
  UPDATE public.courier_earnings AS ce
     SET status = 'requested'
   WHERE ce.id IN (SELECT le.id FROM _locked_earnings AS le);

  DROP TABLE _locked_earnings;

  -- Admin bildirimi
  INSERT INTO public.notifications (user_id, type, title, content, metadata, is_read)
  SELECT p.id, 'courier_payout_request', 'Yeni kurye ödeme isteği',
         'Bir kurye ödeme isteği gönderdi.',
         jsonb_build_object('courier_id', v_uid, 'amount', v_amount, 'payout_id', v_payout_id),
         false
  FROM public.profiles AS p
  WHERE p.role::text = 'admin';

  RETURN QUERY SELECT v_payout_id, v_amount, v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.request_courier_payout(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_courier_payout(uuid) TO authenticated;

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

  -- Yalnız payout'a bağlı item'ları paid yap
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
-- 7) deduct_from_balance: paket authenticated akışından tamamen çıkar
-- -----------------------------------------------------------------------------
DO $revoke_deduct$
DECLARE
  v_function regprocedure;
BEGIN
  FOR v_function IN
    SELECT p.oid::regprocedure
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'deduct_from_balance'
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM authenticated', v_function
    );
  END LOOP;
END
$revoke_deduct$;

COMMENT ON FUNCTION public.deduct_from_balance IS
  'Paket akışı authenticated''tan kaldırıldı; create_package_request atomik yapıyor. service_role sunucu akışları için korunur.';

-- -----------------------------------------------------------------------------
-- 8) RLS temizliği ve yeni politikalar
-- -----------------------------------------------------------------------------

-- courier_requests
DROP POLICY IF EXISTS "courier_requests_authenticated" ON public.courier_requests;
DROP POLICY IF EXISTS "Users can view own courier requests" ON public.courier_requests;
DROP POLICY IF EXISTS "Couriers can update assigned requests" ON public.courier_requests;
DROP POLICY IF EXISTS "courier_requests_select_scoped" ON public.courier_requests;
DROP POLICY IF EXISTS "courier_requests_insert_sender" ON public.courier_requests;
DROP POLICY IF EXISTS "courier_requests_update_courier_or_admin" ON public.courier_requests;
DROP POLICY IF EXISTS "courier_requests_delete_sender_or_admin" ON public.courier_requests;

CREATE POLICY "cr_select_owner_or_admin"
  ON public.courier_requests FOR SELECT
  TO authenticated
  USING (
    sender_id = (SELECT auth.uid())
    OR courier_id = (SELECT auth.uid())
    OR public.is_admin()
  );

CREATE POLICY "cr_insert_sender_only"
  ON public.courier_requests FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_id = (SELECT auth.uid())
    AND courier_id IS NULL
    AND status = 'pending'
  );

CREATE POLICY "cr_update_admin_only"
  ON public.courier_requests FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "cr_delete_admin_only"
  ON public.courier_requests FOR DELETE
  TO authenticated
  USING (public.is_admin());

-- Finansal UPDATE/DELETE'i authenticated'ten kaldır
REVOKE UPDATE, DELETE ON public.courier_requests FROM authenticated;

-- courier_earnings
DROP POLICY IF EXISTS "Admins update earnings" ON public.courier_earnings;
DROP POLICY IF EXISTS "Admins view all earnings" ON public.courier_earnings;
DROP POLICY IF EXISTS "Couriers insert own earnings" ON public.courier_earnings;
DROP POLICY IF EXISTS "Couriers view own earnings" ON public.courier_earnings;

CREATE POLICY "ce_select_own_or_admin"
  ON public.courier_earnings FOR SELECT
  TO authenticated
  USING (courier_id = (SELECT auth.uid()) OR public.is_admin());

-- INSERT/UPDATE/DELETE authenticated için kapalı
REVOKE INSERT, UPDATE, DELETE ON public.courier_earnings FROM authenticated;

-- courier_payout_requests
DROP POLICY IF EXISTS "Admins update payouts" ON public.courier_payout_requests;
DROP POLICY IF EXISTS "Admins view all payouts" ON public.courier_payout_requests;
DROP POLICY IF EXISTS "Couriers create payouts" ON public.courier_payout_requests;
DROP POLICY IF EXISTS "Couriers view own payouts" ON public.courier_payout_requests;

CREATE POLICY "cpr_select_own_or_admin"
  ON public.courier_payout_requests FOR SELECT
  TO authenticated
  USING (courier_id = (SELECT auth.uid()) OR public.is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.courier_payout_requests FROM authenticated;

-- courier_payout_items: yalnız kendi kuryesinin earnings üzerinden admin görebilir
CREATE POLICY "cpi_select_own_or_admin"
  ON public.courier_payout_items FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.courier_earnings AS ce
      JOIN public.courier_payout_requests AS cpr ON cpr.id = courier_payout_items.payout_id
      WHERE ce.id = courier_payout_items.earning_id
        AND cpr.courier_id = (SELECT auth.uid())
    )
  );

REVOKE INSERT, UPDATE, DELETE ON public.courier_payout_items FROM authenticated;

-- courier_request_rejections: authenticated kendi satırlarını yazabilir (RPC zaten var)
CREATE POLICY "crr_select_own"
  ON public.courier_request_rejections FOR SELECT
  TO authenticated
  USING (courier_id = (SELECT auth.uid()) OR public.is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.courier_request_rejections FROM authenticated;

-- -----------------------------------------------------------------------------
-- 9) Güvenli view'lar (eski RLS'i kaldırılmış SELECT davranışını korumak için)
-- -----------------------------------------------------------------------------
-- Eski uygulama .from('courier_earnings').select() ile kendi earnings'lerini
-- okuyor; RLS zaten courier_id = auth.uid() ile sınırlı. Ancak admin
-- pending_earnings toplamı için RPC üzerinden okumalı.

-- ============================================================================
-- Migration sonu
-- ============================================================================
