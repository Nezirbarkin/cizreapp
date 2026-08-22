-- ============================================================================
-- Kurye heading (gidiş yönü) desteği
-- ----------------------------------------------------------------------------
-- AMAÇ: Müşteri paket-gönder haritasında kurye marker'ı yalnız konum değil,
-- gidiş yönünü de göstersin (şehiriçi `current_heading` deseniyle aynı).
-- Pin yerine yön oklu disk kullanıldığı için heading olmadığında da görsel
-- bozulmaz: rotation NULL/0 ise ok yukarı (kuzey) bakar.
--
-- DEĞİŞİKLİKLER:
--   1) profiles.last_known_heading real sütunu (idempotent).
--   2) set_my_courier_location(p_lat, p_lng, p_heading) — 3. parametre
--      DEFAULT NULL; mevcut 2-param çağrıları (p_heading göndermeyenler)
--      hâlâ çalışır. Gövde yetki/sınır denetimi AYNEN KORUNUR.
--   3) get_nearby_couriers RETURNS TABLE'ine heading eklendi; SELECT
--      p.last_known_heading döner (PII değil, yuvarlamaya gerek yok).
--
-- İMZALAR değişti (parametre/return sütun sayısı) → DROP + CREATE.
-- Yetkiler (REVOKE/GRANT), SECURITY DEFINER, search_path='' AYNEN.
-- ============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_known_heading real;

-- (1) set_my_courier_location: heading ekle ----------------------------------
DROP FUNCTION IF EXISTS public.set_my_courier_location(double precision, double precision);

CREATE FUNCTION public.set_my_courier_location(
  p_lat double precision,
  p_lng double precision,
  p_heading real DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'set_my_courier_location: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_uid;
  IF v_role IS DISTINCT FROM 'courier' THEN
    RAISE EXCEPTION 'set_my_courier_location: not a courier'
      USING ERRCODE = '42501';
  END IF;

  IF p_lat IS NULL OR p_lng IS NULL OR
     p_lat < -90 OR p_lat > 90 OR
     p_lng < -180 OR p_lng > 180 THEN
    RAISE EXCEPTION 'set_my_courier_location: invalid coordinates'
      USING ERRCODE = '22023';
  END IF;

  -- heading: NULL (eski istemciler) veya 0-360 arası. 0 "bilinmiyor/araç
  -- duruyor" anlamında gelebilir; olduğu gibi yazılır, istemci tarafı
  -- null/0 değerini yorumlar. Negatif/360+ değerleri normalleştir.
  IF p_heading IS NOT NULL THEN
    IF p_heading < 0 OR p_heading > 360 OR p_heading::text = 'NaN' THEN
      -- Geçersiz heading'i NULL'a düşür; konum yazımı engellenmesin.
      p_heading := NULL;
    END IF;
  END IF;

  UPDATE public.profiles
    SET last_known_lat = p_lat,
        last_known_lng = p_lng,
        last_known_heading = p_heading,
        last_location_update = NOW()
  WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_courier_location(double precision, double precision, real) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_my_courier_location(double precision, double precision, real)
  TO authenticated, service_role;

-- (2) get_nearby_couriers: heading döndür ----------------------------------
DROP FUNCTION IF EXISTS public.get_nearby_couriers(double precision, double precision, double precision, integer);

CREATE FUNCTION public.get_nearby_couriers(
  p_origin_lat double precision DEFAULT NULL,
  p_origin_lng double precision DEFAULT NULL,
  p_max_km double precision DEFAULT 50,
  p_max_age_seconds integer DEFAULT 600
)
RETURNS TABLE (
  id uuid,
  full_name text,
  username text,
  avatar_url text,
  delivered_count integer,
  approx_lat double precision,
  approx_lng double precision,
  heading real,
  last_location_update timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'get_nearby_couriers: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF NOT private.current_user_is_admin() THEN
    v_role := NULL;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.username,
    p.avatar_url,
    p.delivered_count,
    CASE
      WHEN p.last_location_update IS NULL
        OR p.last_location_update < (NOW() - make_interval(secs => p_max_age_seconds))
        OR COALESCE(p.is_online_enabled, true) = false
        OR p.is_ghost_mode = true
        OR COALESCE(p.profile_is_public, true) = false
        OR p.last_known_lat IS NULL
        OR p.last_known_lng IS NULL
      THEN NULL
      ELSE round(p.last_known_lat::numeric, 3)::double precision
    END AS approx_lat,
    CASE
      WHEN p.last_location_update IS NULL
        OR p.last_location_update < (NOW() - make_interval(secs => p_max_age_seconds))
        OR COALESCE(p.is_online_enabled, true) = false
        OR p.is_ghost_mode = true
        OR COALESCE(p.profile_is_public, true) = false
        OR p.last_known_lat IS NULL
        OR p.last_known_lng IS NULL
      THEN NULL
      ELSE round(p.last_known_lng::numeric, 3)::double precision
    END AS approx_lng,
    -- heading: konum gizliyse (yukarıdaki CASE NULL veriyorsa) heading de
    -- NULL döner; aksi halde olduğu gibi (PII değil, yuvarlamasız).
    CASE
      WHEN p.last_location_update IS NULL
        OR p.last_location_update < (NOW() - make_interval(secs => p_max_age_seconds))
        OR COALESCE(p.is_online_enabled, true) = false
        OR p.is_ghost_mode = true
        OR COALESCE(p.profile_is_public, true) = false
        OR p.last_known_lat IS NULL
        OR p.last_known_lng IS NULL
      THEN NULL
      ELSE p.last_known_heading
    END AS heading,
    p.last_location_update
  FROM public.profiles p
  WHERE p.role = 'courier'::public.user_role
    AND p.is_suspicious = false
  ORDER BY p.last_location_update DESC NULLS LAST
  LIMIT 50;
END;
$$;

REVOKE ALL ON FUNCTION public.get_nearby_couriers(double precision, double precision, double precision, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nearby_couriers(double precision, double precision, double precision, integer)
  TO authenticated, service_role;

DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;