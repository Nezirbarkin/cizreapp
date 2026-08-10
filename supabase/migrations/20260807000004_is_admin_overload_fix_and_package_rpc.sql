-- ============================================================================
-- 20260807000004_is_admin_overload_fix_and_package_rpc.sql
-- ----------------------------------------------------------------------------
-- AMAÇ: Üç sorunu TEK migration'da çözmek:
--   1) 'is_admin() is not unique' (42725) ambiguity — birden fazla
--      public.is_admin() overload'ı var. Bunları tek kanonik implementasyona
--      düşür.
--   2) create_package_request RPC canlıda YOK → "Paket Gönder" butonu
--      PGRST202 hatası alıyor.
--   3) list_available_package_requests için PostgREST schema cache reload
--      (zaten 20260807000003 ile yapıldı; burada yalnızca 1 ve 2'yi çözüyoruz).
--
-- KÖK NEDEN ÖZETİ (2026-08-07 tespit edildi):
--   Canlı DB'de public.is_admin() fonksiyonu birden fazla kez CREATE OR
--   REPLACE edildi. PostgreSQL'de aynı isim + argümansız fakat farklı
--   gövde = AYNI OVERLOAD sayılır. Ancak migration'lar arasında farklı
--   tanımlar girince (20260101, 20260209, 20260803), pg_proc içinde
--   farklı OID'lerle birden fazla satır oluştu. argümansız is_admin()
--   çağrısı artık 42725 hatası veriyor.
--
-- ÇÖZÜM STRATEJİSİ:
--   1) Tüm public.is_admin() overload'larını DROP et.
--   2) Kanonik helper private.current_user_is_admin() varsa
--      public.is_admin()'i ona delege ederek yeniden oluştur.
--      Yoksa inline implementasyon yaz.
--   3) create_package_request ekle.
--   4) Schema cache reload.
--
-- GÜVENLİK: REVOKE/GRANT'lar önceki migration'larla aynı; kanonik helper
--   (private.current_user_is_admin) zaten SECURITY DEFINER.
-- ============================================================================

SET search_path = public, pg_temp;

-- ============================================================================
-- ADIM 1) TANILAMA (dry-run): Kaç is_admin() overload'ı var?
-- ============================================================================
-- Bunu bilmek isteyebilirsiniz; aşağıdaki DO bloğu sessizce yapsa da
-- elle doğrulama için:
--   SELECT count(*) FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'is_admin';
-- ============================================================================

-- ============================================================================
-- ADIM 2) TÜM public.is_admin() OVERLOAD'LARINI SİL
-- ----------------------------------------------------------------------------
-- DROP FUNCTION IF EXISTS ...() — parantezli çağrılar sadece belirli
-- imzaları siler. Tüm overload'ları garantilemek için DO $$ içinde
-- pg_proc'tan çekip döngüyle düşürüyoruz.
-- ============================================================================
DO $$
DECLARE
  v_oid oid;
  v_count int := 0;
BEGIN
  FOR v_oid IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'is_admin'
  LOOP
    EXECUTE format('DROP FUNCTION public.is_admin(%s) CASCADE',
                   pg_get_function_identity_arguments(v_oid));
    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    RAISE NOTICE 'public.is_admin() % overload silindi', v_count;
  ELSE
    RAISE NOTICE 'public.is_admin() bulunamadı (zaten yok)';
  END IF;
END
$$;


-- ============================================================================
-- ADIM 3) KANONİK public.is_admin()'İ YENİDEN OLUŞTUR
-- ----------------------------------------------------------------------------
-- private.current_user_is_admin() varsa delege et (kanonik helper);
-- yoksa inline implementasyon yaz.
-- ============================================================================
DO $fn$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private' AND p.proname = 'current_user_is_admin'
  ) THEN
    -- Kanonik helper mevcut: delege et
    EXECUTE $sql$
      CREATE FUNCTION public.is_admin()
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = ''
      AS $body$
        SELECT private.current_user_is_admin();
      $body$;

      REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
      GRANT EXECUTE ON FUNCTION public.is_admin()
        TO authenticated, service_role;
    $sql$;

    RAISE NOTICE 'public.is_admin() → private.current_user_is_admin() delegasyonu ile yeniden oluşturuldu';
  ELSE
    -- Kanonik helper yok (20260803000006 uygulanmamış): inline fallback
    -- Bu durumda bile SECURITY DEFINER + STABLE kalıyor; sonsuz döngü riski
    -- için profiles.role doğrudan okunur.
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
      GRANT EXECUTE ON FUNCTION public.is_admin()
        TO authenticated, service_role;
    $sql$;

    RAISE NOTICE 'public.is_admin() inline fallback ile yeniden oluşturuldu (helper bulunamadı)';
  END IF;
END
$fn$;


-- ============================================================================
-- ADIM 4) courier_requests TABLOSU + INDEX'LER (HOTFIX BLOK 1)
-- ----------------------------------------------------------------------------
-- Idempotent: kolonlar zaten varsa eklemez. canlıda idempotency_key
-- yoksa ekler; index'i de aynı şekilde güvenli oluşturur.
-- ============================================================================
ALTER TABLE public.courier_requests
  ADD COLUMN IF NOT EXISTS idempotency_key uuid,
  ADD COLUMN IF NOT EXISTS delivery_card_label text,
  ADD COLUMN IF NOT EXISTS delivery_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivery_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivery_confirmed_by uuid
    REFERENCES auth.users(id) ON DELETE SET NULL,
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
-- ADIM 5) create_package_request RPC (HOTFIX BLOK 2)
-- ----------------------------------------------------------------------------
-- 13 parametreli atomik talep: mesafe + ücret + bakiye düşümü + ledger.
-- SECURITY DEFINER; auth.uid() ile çağıran kontrolü; idempotency_key ile
-- tekrar gönderim koruması.
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
  -- 1) Oturum kontrolü
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required | oturum açmanız gerekiyor'
      USING ERRCODE = '42501';
  END IF;

  -- 2) Idempotency: aynı (sender_id, key) daha önce kullanıldıysa mevcut kaydı döner
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

  -- 3) Koordinat doğrulama
  IF p_pickup_lat IS NULL OR p_pickup_lat < -90 OR p_pickup_lat > 90
     OR p_delivery_lat IS NULL OR p_delivery_lat < -90 OR p_delivery_lat > 90
     OR p_pickup_lng IS NULL OR p_pickup_lng < -180 OR p_pickup_lng > 180
     OR p_delivery_lng IS NULL OR p_delivery_lng < -180 OR p_delivery_lng > 180 THEN
    RAISE EXCEPTION 'APP:invalid_coordinates | koordinat aralık dışı'
      USING ERRCODE = '22023';
  END IF;

  -- 4) Zorunlu alanlar
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

  -- 5) Aktif servis ayarları
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

  -- 6) Haversine mesafe (km)
  v_distance_km := round(
    6371 * 2 * asin(sqrt(
      power(sin(radians((p_delivery_lat - p_pickup_lat) / 2.0)), 2)
      + cos(radians(p_pickup_lat)) * cos(radians(p_delivery_lat))
        * power(sin(radians((p_delivery_lng - p_pickup_lng) / 2.0)), 2)
    ))::numeric,
    3
  );

  -- 7) Ücret hesabı
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

  -- 8) Bakiye kilidi
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

  -- 9) Bakiye düşümü
  UPDATE public.user_balances AS ub
     SET balance = ub.balance - v_total_fee,
         total_spent = ub.total_spent + v_total_fee,
         updated_at = now()
   WHERE ub.id = v_balance_id;

  -- 10) Ledger kaydı
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

  -- 11) Talep oluştur
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

  -- 12) Ledger referansını talep ile güncelle
  UPDATE public.balance_transactions AS bt
     SET reference_id = v_request_id
   WHERE bt.id = v_tx_id;

  -- 13) Sonuç
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
  'Sunucu-otoriteli atomik paket talebi: mesafe + ücret + bakiye düşümü + ledger. Idempotent. (2026-08-07 is_admin fix ile yeniden kuruldu)';


-- ============================================================================
-- ADIM 6) PostgREST SCHEMA CACHE RELOAD
-- ----------------------------------------------------------------------------
-- create_package_request + list_available_package_requests yeni/tekrar
-- tanımlandı. PostgREST'in pg_catalog cache'ini yenilemesi şart.
-- ============================================================================
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
  RAISE NOTICE '✓ PostgREST schema cache reload tetiklendi';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'PostgREST reload tetiklenemedi: %. Dashboard > API > '
                'Reload schema cache butonunu kullanın.', SQLERRM;
END;
$$;


-- ============================================================================
-- ADIM 7) DOĞRULAMA (commit sonrası elle çalıştır)
-- ----------------------------------------------------------------------------
-- 1) is_admin() tek overload:
--    SELECT count(*) FROM pg_proc p
--    JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public' AND p.proname = 'is_admin';
--    Beklenen: 1
--
-- 2) is_admin() çağrısı (oturum açıkken):
--    SELECT public.is_admin();
--    Beklenen: t/f (42725 yok)
--
-- 3) create_package_request var:
--    SELECT pronargs FROM pg_proc WHERE proname = 'create_package_request';
--    Beklenen: 13
--
-- 4) Birim test (oturum açıkken):
--    SELECT * FROM public.create_package_request(
--      37.3255, 42.1876, 37.3310, 42.1950,
--      'Test', '0555', 'Alıcı', '0556',
--      'A', 'B', 'detay', 'kırılgan',
--      gen_random_uuid());
--    Beklenen: 1 satır, status=pending, total_fee>0
-- ============================================================================
