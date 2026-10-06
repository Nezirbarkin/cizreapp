-- =============================================================================
-- Görev 3.10 — Şehiriçi durak yönetimi: toplu silme + mantık hataları
-- =============================================================================
-- Toplu silme: admin_delete_sehirici_stops(uuid[]) — tek işlemde siler, etkilenen
-- hatların durak sırasını boşluksuz yeniden numaralar, hangi hatların rotasının
-- güncellenmesi gerektiğini döner. Tek durak silme de artık aynı yoldan geçer.
--
-- Düzeltilen mantık hataları (canlıda incelendi):
--   1) Durak silinince hattın stop_order dizisi boşluklu kalıyordu (CASCADE);
--      sıra artık 0..n-1 yeniden numaralanır.
--   2) "Pasif" yapılan durak kullanıcı haritasında/hat listesinde görünmeye devam
--      ediyordu: get_sehirici_lines_with_stops pasif durakları süzmüyordu.
--   3) Hatta kullanılan bir durak başka ŞEHRE taşınabiliyordu (A şehrinin hattı B
--      şehrinin durağını gösteriyordu). Artık önce hatlardan çıkarılmalı.
--   4) Durak adı boş/boşluk, konum aralık dışı olabiliyordu (yalnız istemci
--      denetliyordu).
--   5) admin_set_sehirici_line_stops istemcinin stop_order değerlerine körü körüne
--      güveniyordu: aynı sıra iki kez gelirse UNIQUE(line_id, stop_order) ile
--      tüm kayıt düşüyordu, boşluklar kalıyordu. Artık verilen sıraya göre (eşitte
--      dizideki yere göre) 0..n-1 atanır.
-- Rota önbelleği (route_polyline) BİLEREK silinmez: yol hâlâ aynı yoldur ve
-- yönetici ekranı durak imzası değişen rotayı "eski" diye gösterir; hattın
-- 2'den az durağı kalırsa rota temizlenir (anlamsızdır).
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Yardımcı: hattın durak sırasını 0..n-1 yeniden numarala
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.sehirici_renumber_line(p_line_id uuid)
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v_count integer;
BEGIN
  -- UNIQUE(line_id, stop_order) çakışmasın diye önce hepsi geçici aralığa.
  UPDATE public.sehirici_line_stops
     SET stop_order = stop_order + 1000000
   WHERE line_id = p_line_id;

  WITH ranked AS (
    SELECT id, (row_number() OVER (ORDER BY stop_order, created_at, id) - 1)::integer AS new_order
      FROM public.sehirici_line_stops
     WHERE line_id = p_line_id
  )
  UPDATE public.sehirici_line_stops ls
     SET stop_order = r.new_order
    FROM ranked r
   WHERE ls.id = r.id;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count < 2 THEN
    UPDATE public.sehirici_lines
       SET route_polyline = NULL
     WHERE id = p_line_id AND route_polyline IS NOT NULL;
  END IF;
  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION private.sehirici_renumber_line(uuid) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- Toplu silme
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_delete_sehirici_stops(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_lines uuid[];
  v_deleted integer;
  v_line uuid;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir' USING ERRCODE = '42501';
  END IF;
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN jsonb_build_object('deleted', 0, 'affected_lines', '[]'::jsonb);
  END IF;
  IF cardinality(p_ids) > 500 THEN
    RAISE EXCEPTION 'Tek seferde en fazla 500 durak silinebilir' USING ERRCODE = 'P0001';
  END IF;

  SELECT array_agg(DISTINCT ls.line_id) INTO v_lines
    FROM public.sehirici_line_stops ls
   WHERE ls.stop_id = ANY (p_ids);

  DELETE FROM public.sehirici_stops WHERE id = ANY (p_ids);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  FOREACH v_line IN ARRAY COALESCE(v_lines, '{}'::uuid[]) LOOP
    PERFORM private.sehirici_renumber_line(v_line);
  END LOOP;

  RETURN jsonb_build_object(
    'deleted', v_deleted,
    'affected_lines', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', l.id,
               'code', l.code,
               'name', l.name,
               'remaining_stops', (SELECT count(*) FROM public.sehirici_line_stops x WHERE x.line_id = l.id)
             ) ORDER BY l.display_order, l.code)
        FROM public.sehirici_lines l
       WHERE l.id = ANY (COALESCE(v_lines, '{}'::uuid[]))
    ), '[]'::jsonb)
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_delete_sehirici_stops(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_sehirici_stops(uuid[]) TO authenticated;

-- Tek durak silme aynı yoldan (sıra yeniden numaralanır). İmza/dönüş aynı.
CREATE OR REPLACE FUNCTION public.admin_delete_sehirici_stop(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  PERFORM public.admin_delete_sehirici_stops(ARRAY[p_id]);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_delete_sehirici_stop(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_sehirici_stop(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- Durak kaydı: sunucu doğrulaması + şehir değişikliği koruması (imza aynı)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_upsert_sehirici_stop(
  p_id uuid,
  p_city_id uuid,
  p_name text,
  p_code text,
  p_lat double precision,
  p_lng double precision,
  p_is_active boolean,
  p_address text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;
  IF btrim(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'Durak adı boş olamaz' USING ERRCODE = 'P0001', HINT = 'SEHIRICI_STOP_NAME_REQUIRED';
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Geçerli bir konum girin' USING ERRCODE = 'P0001', HINT = 'SEHIRICI_STOP_LOCATION_INVALID';
  END IF;
  IF p_id IS NOT NULL AND EXISTS (
    SELECT 1
      FROM public.sehirici_line_stops ls
      JOIN public.sehirici_lines l ON l.id = ls.line_id
     WHERE ls.stop_id = p_id AND l.city_id <> p_city_id
  ) THEN
    RAISE EXCEPTION 'Bu durak başka şehrin hatlarında kullanılıyor; önce o hatlardan çıkarın'
      USING ERRCODE = 'P0001', HINT = 'SEHIRICI_STOP_CITY_IN_USE';
  END IF;

  INSERT INTO public.sehirici_stops (id, city_id, name, code, lat, lng, is_active, address)
  VALUES (
    COALESCE(p_id, gen_random_uuid()),
    p_city_id,
    btrim(p_name),
    NULLIF(TRIM(p_code), ''),
    p_lat,
    p_lng,
    COALESCE(p_is_active, TRUE),
    NULLIF(TRIM(p_address), '')
  )
  ON CONFLICT (id) DO UPDATE SET
    city_id = EXCLUDED.city_id,
    name = EXCLUDED.name,
    code = EXCLUDED.code,
    lat = EXCLUDED.lat,
    lng = EXCLUDED.lng,
    is_active = EXCLUDED.is_active,
    -- Parametre geçilmediyse (NULL) mevcut adres korunur.
    address = COALESCE(EXCLUDED.address, public.sehirici_stops.address),
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$fn$;

-- -----------------------------------------------------------------------------
-- Hat durakları: sıra sunucuda 0..n-1 (imza ve dönüş aynı)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_sehirici_line_stops(p_line_id uuid, p_stops jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
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

  -- Sıra: verilen stop_order'a göre, eşitlikte dizideki yere göre; 0..n-1.
  INSERT INTO public.sehirici_line_stops
    (line_id, stop_id, stop_order, minutes_from_start, distance_km)
  SELECT
    p_line_id,
    (e.elem ->> 'stop_id')::uuid,
    (row_number() OVER (ORDER BY (e.elem ->> 'stop_order')::integer NULLS LAST, e.ord) - 1)::integer,
    COALESCE((e.elem ->> 'minutes_from_start')::integer, 0),
    COALESCE((e.elem ->> 'distance_km')::numeric, 0)
  FROM jsonb_array_elements(p_stops) WITH ORDINALITY AS e(elem, ord);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$fn$;

-- -----------------------------------------------------------------------------
-- Kullanıcı tarafı: pasif duraklar hat listesinde yok (imza ve dönüş aynı)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_sehirici_lines_with_stops(p_city_id uuid)
 RETURNS TABLE(line_id uuid, code text, name text, color_hex text, vehicle_type text, estimated_minutes integer, fare_amount numeric, stops jsonb, route_polyline jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
BEGIN
  RETURN QUERY
  SELECT
    l.id AS line_id,
    l.code,
    l.name,
    l.color_hex,
    l.vehicle_type,
    l.estimated_minutes,
    l.fare_amount,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'stop_id', ls.stop_id,
            'stop_order', ls.stop_order,
            'minutes_from_start', ls.minutes_from_start,
            'distance_km', ls.distance_km,
            'name', s.name,
            'lat', s.lat,
            'lng', s.lng,
            'code', s.code,
            'address', s.address
          ) ORDER BY ls.stop_order
        )
        FROM public.sehirici_line_stops ls
        JOIN public.sehirici_stops s ON ls.stop_id = s.id
        WHERE ls.line_id = l.id
          AND s.is_active
      ),
      '[]'::jsonb
    ) AS stops,
    l.route_polyline
  FROM public.sehirici_lines l
  WHERE l.city_id = p_city_id AND l.is_active = TRUE
  ORDER BY l.display_order, l.code;
END;
$fn$;

COMMIT;

NOTIFY pgrst, 'reload schema';
