-- ============================================================================
-- 20260810000001_fix_missing_package_delivery_functions.sql
-- ----------------------------------------------------------------------------
-- AMAÇ: 20260802000005_secure_courier_delivery_and_payout.sql 'in VERİTABANINDA
-- ESKİ bir taslaktan uygulanmış olması nedeniyle 3 fonksiyonun eksik kalması.
--
-- DURUM TESPİTİ:
--   • 02000005 dosyası içinden yalnızca şu 3 fonksiyon DB'de YOK:
--       - request_package_delivery_confirmation(uuid)
--       - confirm_package_delivery(uuid)
--       - get_assigned_package_details(uuid)
--   • Bu fonksiyonlar olmadan "sipariş onayı" (kurye teslim talebi -> gönderici
--     onayı -> kazanç) akışı PGRST202 ile patlıyor.
--   • 02000005 dosyasının TAMAMINI yeniden uygulamak KIRILGAN: dosya sonundaki
--     "crr_select_own" politikası (satır 1266) zaten DB'de mevcut olduğundan
--     42710 (duplicate_object) hatası veriyor; bu hata tek-transaction'lı
--     çalıştırmada tüm batch'i geri alıyor.
--
-- ÇÖZÜM: Bütün dosyayı tekrar koşmak yerine, yalnızca 3 eksik fonksiyonu +
--   bağımlı kolonları + idempotent earnings index'ini yaratan self-contained,
--   tam idempotent bir onarım. Hiçbir politika dokunulmuyor → crr_select_own
--   çakışması yok. CREATE OR REPLACE / IF NOT EXISTS / DROP IF EXISTS →
--   tekrar koşulsa bile zararsız, veri silmez.
--
-- BAĞIMLILIKLAR (zaten DB'de mevcut, doğrulandı):
--   • public.is_admin()            — 20260101 + 0806 + 080704 + 080705
--   • public.is_courier_role()     — 02000005 satır 117 + 080705
--   • courier_requests temel kolonları (distance_km, total_fee, courier_fee,
--     admin_commission, sender_*, recipient_*, pickup_*, delivery_*, vb.)
--     — create_package_request / accept_package_request DB'de çalıştığına
--       göre mevcut.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) courier_requests: teslimat akışının ihtiyaç duyduğu ek kolonlar
--    (02000005 satır 40-46 ile birebir; IF NOT EXISTS → zararsız)
-- ---------------------------------------------------------------------------
ALTER TABLE public.courier_requests
  ADD COLUMN IF NOT EXISTS idempotency_key uuid,
  ADD COLUMN IF NOT EXISTS delivery_card_label text,
  ADD COLUMN IF NOT EXISTS delivery_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivery_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivery_confirmed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2) courier_earnings: confirm_package_delivery'nin yazdığı kolonlar + partial
--    unique index (ON CONFLICT (package_request_id) ... DO NOTHING bağımlılığı)
-- ---------------------------------------------------------------------------
ALTER TABLE public.courier_earnings
  ADD COLUMN IF NOT EXISTS amount_snapshot numeric(12, 2),
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_earnings_package_request
  ON public.courier_earnings (package_request_id)
  WHERE package_request_id IS NOT NULL;


-- ---------------------------------------------------------------------------
-- 3) get_assigned_package_details: atanmış kurye/sender/admin için tam PII
--    (02000005 satır 526-601 ile birebir)
-- ---------------------------------------------------------------------------
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


-- ---------------------------------------------------------------------------
-- 4) request_package_delivery_confirmation: kurye teslim talebi başlatır
--    (02000005 satır 721-757 ile birebir)
-- ---------------------------------------------------------------------------
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


-- ---------------------------------------------------------------------------
-- 5) confirm_package_delivery: gönderici onayı -> teslim + idempotent earnings
--    + delivered_count atomik artış + çapraz-kullanıcı bildirim
--    (02000005 satır 759-845 ile birebir)
-- ---------------------------------------------------------------------------
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


-- ---------------------------------------------------------------------------
-- 6) PostgREST schema cache'i yeniden yükle (PGRST202 bir daha çıkmasın)
-- ---------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';


-- ---------------------------------------------------------------------------
-- 7) DOĞRULAMA — 3 fonksiyonun artık var olduğunu gösterir
-- ---------------------------------------------------------------------------
SELECT n.nspname AS schema,
       p.proname AS function_name,
       pg_get_function_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'get_assigned_package_details',
    'request_package_delivery_confirmation',
    'confirm_package_delivery'
  )
ORDER BY p.proname;
