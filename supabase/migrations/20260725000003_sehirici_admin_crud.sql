-- =============================================================================
-- Admin CRUD RPC'leri — Şehiriçi servis modülü için
-- =============================================================================
-- RLS BYPASS edip, admin kontrolü yapıp CRUD yapacak SECURITY DEFINER
-- fonksiyonları. service_rolü değil authenticated kullanıcılar da çağırabilir
-- (içeride profiles.role = 'admin' kontrolü yapılır).

-- =============================================================================
-- Yardımcı: admin kontrolü
-- =============================================================================
CREATE OR REPLACE FUNCTION public.auth_sehirici_is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Önce auth_is_admin() fonksiyonuna bak (varsa)
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'auth_is_admin') THEN
    RETURN public.auth_is_admin();
  END IF;
  -- Yoksa profiles.role kontrolü yap
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'::text
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.auth_sehirici_is_admin() TO authenticated;

-- =============================================================================
-- 1) Şehir CRUD
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_upsert_sehirici_city(
  p_id UUID,
  p_name TEXT,
  p_slug TEXT,
  p_center_lat DOUBLE PRECISION,
  p_center_lng DOUBLE PRECISION,
  p_zoom_level INTEGER,
  p_is_active BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_slug TEXT;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  -- slug boşsa name'den üret
  v_slug := COALESCE(NULLIF(TRIM(p_slug), ''), LOWER(REGEXP_REPLACE(p_name, '[^a-zA-Z0-9]+', '-', 'g')));

  INSERT INTO public.sehirici_cities (id, name, slug, center_lat, center_lng, zoom_level, is_active)
  VALUES (COALESCE(p_id, gen_random_uuid()), p_name, v_slug, p_center_lat, p_center_lng, p_zoom_level, COALESCE(p_is_active, TRUE))
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    slug = EXCLUDED.slug,
    center_lat = EXCLUDED.center_lat,
    center_lng = EXCLUDED.center_lng,
    zoom_level = EXCLUDED.zoom_level,
    is_active = EXCLUDED.is_active,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_sehirici_city(UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, BOOLEAN) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_sehirici_city(UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, BOOLEAN) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.admin_delete_sehirici_city(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;
  DELETE FROM public.sehirici_cities WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_sehirici_city(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_delete_sehirici_city(UUID) FROM PUBLIC;

-- =============================================================================
-- 2) Hat CRUD
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_upsert_sehirici_line(
  p_id UUID,
  p_city_id UUID,
  p_code TEXT,
  p_name TEXT,
  p_color_hex TEXT,
  p_vehicle_type TEXT,
  p_estimated_minutes INTEGER,
  p_fare_amount NUMERIC,
  p_is_active BOOLEAN,
  p_display_order INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  INSERT INTO public.sehirici_lines (
    id, city_id, code, name, color_hex, vehicle_type,
    estimated_minutes, fare_amount, is_active, display_order
  )
  VALUES (
    COALESCE(p_id, gen_random_uuid()),
    p_city_id,
    p_code,
    p_name,
    COALESCE(p_color_hex, '#1976D2'),
    COALESCE(NULLIF(p_vehicle_type, ''), 'bus')::sehirici_vehicle_type,
    p_estimated_minutes,
    COALESCE(p_fare_amount, 0),
    COALESCE(p_is_active, TRUE),
    COALESCE(p_display_order, 0)
  )
  ON CONFLICT (id) DO UPDATE SET
    city_id = EXCLUDED.city_id,
    code = EXCLUDED.code,
    name = EXCLUDED.name,
    color_hex = EXCLUDED.color_hex,
    vehicle_type = EXCLUDED.vehicle_type,
    estimated_minutes = EXCLUDED.estimated_minutes,
    fare_amount = EXCLUDED.fare_amount,
    is_active = EXCLUDED.is_active,
    display_order = EXCLUDED.display_order,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_sehirici_line(UUID, UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, NUMERIC, BOOLEAN, INTEGER) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_sehirici_line(UUID, UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, NUMERIC, BOOLEAN, INTEGER) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.admin_delete_sehirici_line(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;
  DELETE FROM public.sehirici_lines WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_sehirici_line(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_delete_sehirici_line(UUID) FROM PUBLIC;

-- =============================================================================
-- 3) Durak CRUD
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_upsert_sehirici_stop(
  p_id UUID,
  p_city_id UUID,
  p_name TEXT,
  p_code TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_active BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  INSERT INTO public.sehirici_stops (id, city_id, name, code, lat, lng, is_active)
  VALUES (
    COALESCE(p_id, gen_random_uuid()),
    p_city_id,
    p_name,
    NULLIF(TRIM(p_code), ''),
    p_lat,
    p_lng,
    COALESCE(p_is_active, TRUE)
  )
  ON CONFLICT (id) DO UPDATE SET
    city_id = EXCLUDED.city_id,
    name = EXCLUDED.name,
    code = EXCLUDED.code,
    lat = EXCLUDED.lat,
    lng = EXCLUDED.lng,
    is_active = EXCLUDED.is_active,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_sehirici_stop(UUID, UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_sehirici_stop(UUID, UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.admin_delete_sehirici_stop(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;
  DELETE FROM public.sehirici_stops WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_sehirici_stop(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_delete_sehirici_stop(UUID) FROM PUBLIC;

-- =============================================================================
-- 4) Şoför CRUD
-- =============================================================================
-- Şoför profili oluştur / güncelle / sil
CREATE OR REPLACE FUNCTION public.admin_upsert_sehirici_driver(
  p_id UUID,
  p_profile_id UUID,
  p_license_number TEXT,
  p_phone TEXT,
  p_status TEXT,
  p_assigned_line_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  INSERT INTO public.sehirici_drivers (id, profile_id, license_number, phone, status, assigned_line_id)
  VALUES (
    COALESCE(p_id, gen_random_uuid()),
    p_profile_id,
    NULLIF(TRIM(p_license_number), ''),
    NULLIF(TRIM(p_phone), ''),
    COALESCE(NULLIF(p_status, ''), 'active')::public.sehirici_driver_status,
    p_assigned_line_id
  )
  ON CONFLICT (id) DO UPDATE SET
    profile_id = EXCLUDED.profile_id,
    license_number = EXCLUDED.license_number,
    phone = EXCLUDED.phone,
    status = EXCLUDED.status,
    assigned_line_id = EXCLUDED.assigned_line_id,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_sehirici_driver(UUID, UUID, TEXT, TEXT, TEXT, UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_sehirici_driver(UUID, UUID, TEXT, TEXT, TEXT, UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.admin_delete_sehirici_driver(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;
  DELETE FROM public.sehirici_drivers WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_sehirici_driver(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_delete_sehirici_driver(UUID) FROM PUBLIC;
