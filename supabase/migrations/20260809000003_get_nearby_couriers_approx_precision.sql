-- ============================================================================
-- get_nearby_couriers: approx konum yuvarlaması 2 → 3 ondalık
-- ----------------------------------------------------------------------------
-- AMAÇ: müşteri paket gönder haritasındaki kurye marker'ı gerçek konumdan
-- ~1.1 km sapan bir grid noktasında gösteriliyordu — `round(lat, 2)` (0.01°)
-- yüzünden. Bu, "motokurye konumu yanlış" şikayetinin nedeni. Orijinal
-- migration yorumu zaten ~110m (0.001°) hedefliyordu ama kod 2 ondalık
-- kullanıyordu; yorum ile kod çelişiyordu.
--
-- DÜZELTME: round(..., 2) → round(..., 3). 3 ondalık = 0.001° ≈ 111m. Bu
-- yine PII koruması sağlar (bin/mahalle düzeyinde gizler, tam konum ifşa
-- etmez) ama kuryeyi doğru yola yakın gösterir. İmza, yetkiler, SECURITY
-- DEFINER, filtre mantığı (online, ghost, public, yaş) AYNEN KORUNUR →
-- test 005 (profiles_security_invariants) geçer.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_nearby_couriers(
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
      -- 3 ondalık = 0.001° ≈ 111m. Tam konum ifşa etmeden kuryeyi doğru yola
      -- yakın gösterir (önceki 2 ondalık ~1.1 km sapıyordu).
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