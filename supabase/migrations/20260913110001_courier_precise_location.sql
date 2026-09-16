-- ============================================================================
-- get_nearby_couriers: adminlere TAM konum, diğerlerine ~11 m hassasiyet
-- ----------------------------------------------------------------------------
-- SORUN: kurye marker'ı haritada gerçek konumunda görünmüyor ve hareket
-- etmiyordu. İki nedeni vardı:
--   1) Konum `round(lat, 3)` ile 0.001° (~111 m) karelajına yuvarlanıyordu.
--      Kurye 100 m ilerlese bile aynı grid noktasında kalıyor, sonra bir
--      anda 111 m zıplıyordu: "hareket" yerine ışınlanma görüntüsü.
--      Yuvarlama aynı zamanda marker'ı yanlış sokağa/yola oturtuyordu.
--   2) Bu fonksiyon `private.current_user_is_admin()` çağırıyor ama sonucunu
--      HİÇ KULLANMIYORDU (v_role atanıp bırakılıyordu) — admin panelinden
--      bakan yönetici de müşteriyle aynı yuvarlanmış konumu görüyordu.
--
-- ÇÖZÜM:
--   • Admin (private.current_user_is_admin() = true) → ham
--     last_known_lat/lng, yuvarlama yok. Yönetici operasyonu gerçek konum
--     üzerinden izler (bu RPC zaten yalnız authenticated'a GRANT'li).
--   • Diğer kullanıcılar → round(..., 4) = 0.0001° ≈ 11 m. Marker doğru
--     sokakta ve gerçekten akıcı hareket ediyor; ham GPS fix'i (accuracy
--     dahil) yine ifşa edilmiyor.
--   • Gizlilik filtreleri (online kapalı / ghost mode / profil gizli /
--     konum eski / konum yok) AYNEN korunur; bu koşullarda lat/lng/heading
--     hâlâ NULL döner.
--
-- İmza ve dönen sütunlar DEĞİŞMEDİ → CREATE OR REPLACE yeterli, yetkiler
-- ve istemci sözleşmesi bozulmaz.
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
  v_is_admin boolean;
  -- Admin ham konumu görür; diğerleri 4 ondalığa (≈11 m) yuvarlanmış.
  v_precision integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'get_nearby_couriers: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  v_is_admin := private.current_user_is_admin();
  v_precision := CASE WHEN v_is_admin THEN NULL ELSE 4 END;

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
      WHEN v_precision IS NULL THEN p.last_known_lat
      ELSE round(p.last_known_lat::numeric, v_precision)::double precision
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
      WHEN v_precision IS NULL THEN p.last_known_lng
      ELSE round(p.last_known_lng::numeric, v_precision)::double precision
    END AS approx_lng,
    -- heading: konum gizliyse heading de NULL döner; aksi halde olduğu gibi
    -- (PII değil, yuvarlamasız). Marker'ın gittiği yöne dönmesi için gerekli.
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

COMMENT ON FUNCTION public.get_nearby_couriers(double precision, double precision, double precision, integer) IS
  'Konum paylaşan kuryeler. Admin ham konumu görür; diğer kullanıcılar 4 ondalığa (~11 m) yuvarlanmış konumu görür. Gizlilik filtreleri (ghost/online/public/yaş) korunur.';

DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;
