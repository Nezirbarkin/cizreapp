-- ============================================================================
-- create_package_request: kuş uçuşu (Haversine) → gerçek yol mesafesi
-- ----------------------------------------------------------------------------
-- AMAÇ: paket gönder/al ekranında km ve ücret, en kısa araç yoluna göre
-- hesaplansın — bağlı fonksiyonları (RPC imzası, yetkileri, bakiye/ledger/
-- idempotity akışı, test 007) bozmadan.
--
-- YAKLAŞIM: RPC içinden senkron HTTP (pg_net) bu projede kullanılamaz (worker
-- 30+ sn gecikmeli). Bunun yerine mesafe, sunucu otoriteli bir Edge Function
-- (route-distance) tarafından Google Directions ile hesaplanır ve
-- road_distance_cache tablosuna yazılır. RPC, yalnızca bu önbelleği okur:
-- 6. adımda önce Haversine baseline, ardından aynı (yuvarlanmış) koordinatlar
-- için önbellekte gerçek yol mesafesi varsa onunla override. Önbellek miss
-- durumunda Haversine kalır — fiyat asla 0/NULL olmaz, kırılma yok.
--
-- GÜVENLİK: önbellek yalnızca service-role Edge Function tarafından yazılır
-- (Google Directions sonucu). İstemci mesafe gönderemez; RPC koordinatları
-- alır, sunucu-tabanlı önbelleğe bakar. Sözleşme (13 param, authenticated
-- EXECUTE, SECURITY DEFINER, r_ önekli RETURNS TABLE, skaler idempotity
-- değişkenleri, bakiye/ledger akışı) AYNEN KORUNUR → test 007 geçer.
--
-- Önkoşul: route-distance Edge Function deploy edilmeli + Google API key'in
-- Directions API yetkisi GCP'de açık olmalı. Key app_about_settings'den
-- okunur (Edge Function service-role ile).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) road_distance_cache tablosu (sunucu otoriteli yol mesafesi önbelleği)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.road_distance_cache (
  pickup_lat    numeric(9,6)  NOT NULL,
  pickup_lng    numeric(9,6)  NOT NULL,
  delivery_lat  numeric(9,6)  NOT NULL,
  delivery_lng  numeric(9,6)  NOT NULL,
  distance_km   numeric(10,3) NOT NULL,
  duration_s    integer,
  fetched_at    timestamptz  NOT NULL DEFAULT now()
);

-- Koordinat çifti başına tek kayıt. RPC bu anahtarla okur.
CREATE UNIQUE INDEX IF NOT EXISTS uq_road_distance_cache_coords
  ON public.road_distance_cache (pickup_lat, pickup_lng, delivery_lat, delivery_lng);

-- RPC (SECURITY DEFINER = owner yetkisi) okur. Edge Function (service role)
-- yazar/upsert eder. RLS kapalı bırakılır; erişim rol bazlı denetlenir.
ALTER TABLE public.road_distance_cache ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.road_distance_cache FROM PUBLIC, anon;
-- authenticated ve service_role SELECT edebilsin (RPC authenticated bağlamında
-- çalışır; service_role Edge Function upsert için tam yetki).
GRANT SELECT ON public.road_distance_cache TO authenticated;
GRANT ALL ON public.road_distance_cache TO service_role;

-- ----------------------------------------------------------------------------
-- 2) create_package_request: 6. adım mesafe bloğu önbellek okumasıyla
-- ----------------------------------------------------------------------------
SET search_path = '';

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
  r_id              uuid,
  r_status          text,
  r_total_fee       numeric,
  r_courier_fee     numeric,
  r_admin_commission numeric,
  r_distance_km     numeric,
  r_created_at      timestamptz
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
  v_ex_id           uuid;
  v_ex_status       text;
  v_ex_total_fee    numeric;
  v_ex_courier_fee  numeric;
  v_ex_admin_fee    numeric;
  v_ex_distance_km  numeric;
  v_ex_created_at   timestamptz;
  v_road_km         numeric;
BEGIN
  -- 1) Oturum kontrolü
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required | oturum açmanız gerekiyor'
      USING ERRCODE = '42501';
  END IF;

  -- 2) Idempotency
  IF p_idempotency_key IS NOT NULL THEN
    SELECT cr.id, cr.status::text, cr.total_fee, cr.courier_fee,
           cr.admin_commission, cr.distance_km, cr.created_at
      INTO v_ex_id, v_ex_status, v_ex_total_fee, v_ex_courier_fee,
           v_ex_admin_fee, v_ex_distance_km, v_ex_created_at
    FROM public.courier_requests AS cr
    WHERE cr.sender_id = v_user_id
      AND cr.idempotency_key = p_idempotency_key
    LIMIT 1;

    IF v_ex_id IS NOT NULL THEN
      r_id               := v_ex_id;
      r_status           := v_ex_status;
      r_total_fee        := v_ex_total_fee;
      r_courier_fee      := v_ex_courier_fee;
      r_admin_commission := v_ex_admin_fee;
      r_distance_km      := v_ex_distance_km;
      r_created_at       := v_ex_created_at;
      RETURN NEXT;
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

  -- 6) Mesafe (km)
  --    Önce Haversine (kuş uçuşu) baseline — aynı zamanda fallback.
  --    Sonra road_distance_cache'ten (route-distance Edge Function tarafından
  --    Google Directions ile doldurulur) aynı koordinatlar için gerçek yol
  --    mesafesini oku; varsa onunla override. Miss -> Haversine kalır.
  --    Koordinatlar 5 ondalık (~1m) ile yuvarlanır; istemci önizlemesi ve RPC
  --    aynı anahtarı kullanır.
  v_distance_km := round(
    6371 * 2 * asin(sqrt(
      power(sin(radians((p_delivery_lat - p_pickup_lat) / 2.0)), 2)
      + cos(radians(p_pickup_lat)) * cos(radians(p_delivery_lat))
        * power(sin(radians((p_delivery_lng - p_pickup_lng) / 2.0)), 2)
    ))::numeric,
    3
  );

  BEGIN
    SELECT c.distance_km INTO v_road_km
    FROM public.road_distance_cache AS c
    WHERE c.pickup_lat   = round(p_pickup_lat::numeric, 5)
      AND c.pickup_lng   = round(p_pickup_lng::numeric, 5)
      AND c.delivery_lat = round(p_delivery_lat::numeric, 5)
      AND c.delivery_lng = round(p_delivery_lng::numeric, 5)
      AND c.fetched_at > now() - interval '30 days'
    LIMIT 1;

    IF v_road_km IS NOT NULL AND v_road_km > 0 THEN
      v_distance_km := v_road_km;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Önbellek okunamazsa Haversine baseline korunur.
    NULL;
  END;

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
  r_id               := v_request_id;
  r_status           := 'pending';
  r_total_fee        := v_total_fee;
  r_courier_fee      := v_courier_fee;
  r_admin_commission := v_admin_fee;
  r_distance_km      := v_distance_km;
  r_created_at       := v_created_at;
  RETURN NEXT;
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
  'Sunucu-otoriteli atomik paket talebi: gerçek yol mesafesi (road_distance_cache, route-distance Edge Function doldurur) + Haversine fallback + ücret + bakiye düşümü + ledger. Idempotent. '
  '(2026-08-08 HOTFIX v2: r_ önekli RETURNS TABLE. 2026-08-09: mesafe kaynağı Haversine → yol mesafesi önbelleği, fallback Haversine.)';

DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;