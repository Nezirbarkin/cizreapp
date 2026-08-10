-- ============================================================================
-- HOTFIX — create_package_request eksik (PGRST202)
-- ----------------------------------------------------------------------------
-- Belirti (Flutter): PostgrestException PGRST202
--   "Could not find the function public.create_package_request(...) in the
--    schema cache ... hint: Perhaps you meant to call the function
--    public.create_cancellation_request"
--
-- Kök neden: 20260802000005_secure_courier_delivery_and_payout.sql migration'ı
-- canlıya HİÇ uygulanmamış. create_package_request fonksiyonu kataloğda yok.
-- (Bkz. diagnostics/BULGALAR_20260805.md — repo/canlı ayrışması.)
--
-- Bu hotfix, migration'ın yalnızca PAKET GÖNDERİM için gerekli güvenli
-- kısmını uygular: courier_requests sütunları (idempotent) + atomik RPC.
--
-- UYGULAMAYIN (henüz): migration'ın 7. (deduct_from_balance REVOKE) ve
-- 8. (RLS + courier_earnings/payout REVOKE) bölümleri. Sebep: sipariş
-- teslimat akışı hâlâ doğrudan courier_earnings INSERT ediyor
-- (lib/features/courier/screens/courier_panel_screen.dart:3046). Bu kısım
-- bir RPC'ye taşınana kadar REVOKE uygulanırsa sipariş teslimat kazanç
-- kaydı kırılır.
--
-- KULLANIM:
--   1) Önce aşağıdaki BLOK 0 (salt-okunur tanılama) çalıştır, çıktıyı kontrol et.
--   2) Bağımlılıklar tamam ise BLOK 1 + BLOK 2'yi uygula.
--   3) NOTYFY pgrst ile şema önbelleğini yenile.
-- ============================================================================


-- ============================================================================
-- BLOK 0 — TANILAMA (salt-okunur, hiçbir şey değiştirmez)
-- ----------------------------------------------------------------------------
-- create_package_request YOK mu? Bağımlılıklar VAR mı?
-- Beklenen: create_package_request satırı BOŞ döner; diğerleri dolu.
-- ============================================================================
SELECT 'create_package_request' AS nesne,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_package_request'
  ) THEN 'VAR' ELSE 'YOK (beklenen)' END AS durum;

-- Bağımlı tablolar
SELECT t.relname AS tablo, 'VAR' AS durum
FROM pg_class t JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'public'
  AND t.relname IN ('courier_requests','courier_service_settings',
                    'user_balances','balance_transactions');

-- courier_requests.idempotency_key kolonu var mı
SELECT attname AS kolon,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'public.courier_requests'::regclass
      AND attname = 'idempotency_key' AND NOT attisdropped
  ) THEN 'VAR' ELSE 'YOK (BLOK 1 ekleyecek)' END AS durum
FROM (VALUES ('idempotency_key')) v(attname);

-- balance_transaction_type enum'unda 'courier_payment' değeri var mı
-- (yoksa RPC çalışma anında hata verir; önce o enum değerini eklemek gerekir)
SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type ty ON ty.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = ty.typnamespace
    WHERE n.nspname = 'public' AND ty.typname = 'balance_transaction_type'
      AND e.enumlabel = 'courier_payment'
  ) THEN 'VAR (OK)' ELSE 'YOK — RPC çağrısı patlar, önce ekle!' END AS courier_payment_enum;


-- ============================================================================
-- BLOK 1 — courier_requests sütunları + idempotency index'i (idempotent)
-- ============================================================================
SET search_path = public, pg_temp;

ALTER TABLE public.courier_requests
  ADD COLUMN IF NOT EXISTS idempotency_key uuid,
  ADD COLUMN IF NOT EXISTS delivery_card_label text,
  ADD COLUMN IF NOT EXISTS delivery_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivery_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivery_confirmed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_requests_sender_idem
  ON public.courier_requests (sender_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_courier_requests_status_created_at
  ON public.courier_requests (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_courier_requests_pending_pool
  ON public.courier_requests (status, created_at DESC)
  WHERE status = 'pending' AND courier_id IS NULL;


-- ============================================================================
-- BLOK 2 — create_package_request: atomik talep + bakiye düşümü + ledger
-- (migration 20260802000005 bölüm 2A'nın birebir kopyası)
-- ============================================================================
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
    'courier_request', gen_random_uuid(),
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
  'Sunucu-otoriteli atomik paket talebi: mesafe + ücret + bakiye düşümü + ledger. Idempotent. (HOTFIX: canlıya eksik kalmıştı)';


-- ============================================================================
-- BLOK 3 — PostgREST şema önbelleğini yenile (fonksiyon görünür olsun)
-- ============================================================================
NOTIFY pgrst, 'reload schema';
