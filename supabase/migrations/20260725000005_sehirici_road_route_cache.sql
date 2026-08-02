-- =============================================================================
-- Şehiriçi: gerçek yol/cadde rotası önbellekleme
-- Tarih: 2026-07-25
-- Amaç: Harita üzerinde durakları düz çizgiyle değil, caddeleri takip eden bir
-- rota (OSRM/Directions API sonucu) ile çizmek. API her harita açılışında
-- yeniden çağrılmasın diye sonuç sehirici_lines.route_polyline (JSONB) alanında
-- kalıcı olarak önbelleğe alınır — hat/duraklar değişmediği sürece tekrar
-- API çağrısı yapılmaz.
-- =============================================================================

-- get_sehirici_lines_with_stops artık önbellekteki route_polyline'ı da döndürsün.
-- Dönüş tipi (OUT parametreleri) değiştiği için CREATE OR REPLACE yetmez,
-- önce eski fonksiyon imzası DROP edilmeli.
DROP FUNCTION IF EXISTS public.get_sehirici_lines_with_stops(UUID);

CREATE OR REPLACE FUNCTION public.get_sehirici_lines_with_stops(p_city_id UUID)
RETURNS TABLE (
  line_id UUID,
  code TEXT,
  name TEXT,
  color_hex TEXT,
  vehicle_type sehirici_vehicle_type,
  estimated_minutes INTEGER,
  fare_amount NUMERIC,
  stops JSONB,
  route_polyline JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
            'lng', s.lng
          ) ORDER BY ls.stop_order
        )
        FROM public.sehirici_line_stops ls
        JOIN public.sehirici_stops s ON ls.stop_id = s.id
        WHERE ls.line_id = l.id
      ),
      '[]'::jsonb
    ) AS stops,
    l.route_polyline
  FROM public.sehirici_lines l
  WHERE l.city_id = p_city_id AND l.is_active = TRUE
  ORDER BY l.display_order, l.code;
END;
$$;

-- DROP FUNCTION önceki GRANT'leri de kaldırdığından yeniden veriliyor.
GRANT EXECUTE ON FUNCTION public.get_sehirici_lines_with_stops(UUID) TO authenticated, anon;

-- Herhangi bir kimliği doğrulanmış kullanıcının, hesapladığı yol rotasını
-- (OSRM sonucu) önbelleğe yazabilmesi için — sehirici_lines_admin_all politikası
-- yalnızca admin'e UPDATE izni verdiğinden, normal kullanıcılar/şoförler
-- harita açtığında hesaplanan rotayı kaydedemez ve her seferinde API'ye
-- tekrar gidilir. Bu RPC dar kapsamlı bir bypass sağlar: SADECE route_polyline
-- alanını günceller, aynı hattın durak dizilimine karşılık gelen imzayı (stop
-- sırası hash'i) doğrular ki keyfi/zararlı veri yazılamasın.
CREATE OR REPLACE FUNCTION public.cache_sehirici_route_polyline(
  p_line_id UUID,
  p_stops_signature TEXT,
  p_polyline JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_signature TEXT;
BEGIN
  SELECT md5(string_agg(ls.stop_id::text, ',' ORDER BY ls.stop_order))
    INTO v_signature
  FROM public.sehirici_line_stops ls
  WHERE ls.line_id = p_line_id;

  IF v_signature IS NULL OR v_signature != p_stops_signature THEN
    RAISE EXCEPTION 'Durak imzası uyuşmuyor, önbellek yazılamadı';
  END IF;

  UPDATE public.sehirici_lines
  SET route_polyline = p_polyline
  WHERE id = p_line_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cache_sehirici_route_polyline(UUID, TEXT, JSONB) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.cache_sehirici_route_polyline(UUID, TEXT, JSONB) FROM PUBLIC;

COMMENT ON COLUMN public.sehirici_lines.route_polyline IS
  'Önbelleğe alınmış yol-takip eden rota: {"points": [[lat,lng], ...], "stops_signature": "...", "source": "osrm", "cached_at": "..."}';
