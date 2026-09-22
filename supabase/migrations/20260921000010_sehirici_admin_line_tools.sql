-- =============================================================================
-- ŞEHİRİÇİ — ADMIN HAT ARAÇLARI
-- Tarih: 2026-09-21
--
--  1) admin_set_sehirici_line_stops: hattın duraklarını TEK İŞLEMDE değiştirir.
--     Eskiden istemci "önce hepsini sil, sonra yeniden ekle" diye iki ayrı
--     istek atıyordu; ikincisi (ağ kesilmesi, hatalı sıra…) başarısız olursa
--     hat DURAKSIZ kalıyordu. Tek RPC içinde silme+ekleme birlikte ya olur ya olmaz.
--  2) admin_reorder_sehirici_lines: hatların listedeki sırasını (display_order)
--     tek çağrıyla kaydeder — sıra ekranda hiç düzenlenemiyordu.
--  3) get_sehirici_active_trips: şoförün çalışma saatlerini de döner. İstemci
--     modeli bu alanları okuyordu ama RPC hiç göndermediği için "Çalışma
--     saatleri" satırı araç kartında ASLA görünmüyordu.
--
-- İdempotent: tekrar çalıştırılabilir.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Hat duraklarını atomik değiştir
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_sehirici_line_stops(
  p_line_id uuid,
  p_stops jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_city uuid;
  v_count integer;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  SELECT city_id INTO v_city FROM public.sehirici_lines WHERE id = p_line_id;
  IF v_city IS NULL THEN
    RAISE EXCEPTION 'Hat bulunamadı';
  END IF;

  IF p_stops IS NULL OR jsonb_typeof(p_stops) <> 'array' THEN
    RAISE EXCEPTION 'Durak listesi bir dizi olmalı';
  END IF;

  -- Her durak var mı ve hattın şehrinde mi?
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_stops) AS x(stop_id uuid)
    LEFT JOIN public.sehirici_stops s ON s.id = x.stop_id
    WHERE s.id IS NULL OR s.city_id <> v_city
  ) THEN
    RAISE EXCEPTION 'Bir durak bulunamadı ya da başka bir şehre ait';
  END IF;

  -- Aynı durak hatta iki kez eklenemez (UNIQUE(line_id, stop_id)).
  IF (
    SELECT count(*) <> count(DISTINCT x.stop_id)
    FROM jsonb_to_recordset(p_stops) AS x(stop_id uuid)
  ) THEN
    RAISE EXCEPTION 'Aynı durak hatta iki kez eklenemez';
  END IF;

  DELETE FROM public.sehirici_line_stops WHERE line_id = p_line_id;

  INSERT INTO public.sehirici_line_stops
    (line_id, stop_id, stop_order, minutes_from_start, distance_km)
  SELECT
    p_line_id,
    x.stop_id,
    x.stop_order,
    COALESCE(x.minutes_from_start, 0),
    COALESCE(x.distance_km, 0)
  FROM jsonb_to_recordset(p_stops) AS x(
    stop_id uuid,
    stop_order integer,
    minutes_from_start integer,
    distance_km numeric
  );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_sehirici_line_stops(uuid, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_sehirici_line_stops(uuid, jsonb)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 2) Hat sırasını kaydet
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reorder_sehirici_lines(
  p_city_id uuid,
  p_line_ids uuid[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_count integer;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  UPDATE public.sehirici_lines l
     SET display_order = t.ord::integer,
         updated_at = now()
    FROM unnest(p_line_ids) WITH ORDINALITY AS t(id, ord)
   WHERE l.id = t.id AND l.city_id = p_city_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reorder_sehirici_lines(uuid, uuid[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reorder_sehirici_lines(uuid, uuid[])
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) Aktif seferler: çalışma saatleri eklendi (dönüş tipi değiştiği için DROP + CREATE)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_sehirici_active_trips(uuid);

CREATE FUNCTION public.get_sehirici_active_trips(p_city_id uuid DEFAULT NULL)
RETURNS TABLE (
  trip_id uuid,
  line_id uuid,
  line_code text,
  line_name text,
  line_color text,
  driver_name text,
  current_lat double precision,
  current_lng double precision,
  current_heading real,
  current_speed real,
  started_at timestamptz,
  next_stop_id uuid,
  next_stop_name text,
  next_stop_lat double precision,
  next_stop_lng double precision,
  eta_minutes integer,
  status sehirici_trip_status,
  working_hours_start text,
  working_hours_end text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id AS trip_id,
    t.line_id,
    l.code AS line_code,
    l.name AS line_name,
    l.color_hex AS line_color,
    COALESCE(p.full_name, 'Şoför') AS driver_name,
    t.current_lat,
    t.current_lng,
    t.current_heading,
    t.current_speed,
    t.started_at,
    t.next_stop_id,
    ns.name AS next_stop_name,
    ns.lat AS next_stop_lat,
    ns.lng AS next_stop_lng,
    t.eta_minutes,
    t.status,
    d.working_hours_start,
    d.working_hours_end
  FROM public.sehirici_trips t
  JOIN public.sehirici_lines l ON t.line_id = l.id
  LEFT JOIN public.sehirici_drivers d ON t.driver_id = d.id
  LEFT JOIN public.profiles p ON d.profile_id = p.id
  LEFT JOIN public.sehirici_stops ns ON t.next_stop_id = ns.id
  WHERE t.status IN ('active', 'paused')
    AND (p_city_id IS NULL OR l.city_id = p_city_id)
  ORDER BY t.started_at DESC NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.get_sehirici_active_trips(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sehirici_active_trips(uuid)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
