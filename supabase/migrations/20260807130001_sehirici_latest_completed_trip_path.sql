-- =============================================================================
-- Şehiriçi: Son tamamlanmış seferin yol noktaları
-- Tarih: 2026-08-07
-- Amaç: Admin'in bir hattın "Son Seferden Öner" akışı için, hattın en son
-- 'completed' seferine ait tüm GPS noktalarını (lat/lng/recorded_at) tek sorguda
-- döndürmek. Draw dialog bu noktaları Douglas-Peucker ile sadeleştirip
-- route_polyline olarak yazar.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_sehirici_latest_completed_trip_path(
  p_line_id UUID
)
RETURNS TABLE (
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT tl.lat, tl.lng, tl.recorded_at
  FROM public.sehirici_trip_locations tl
  JOIN public.sehirici_trips t ON t.id = tl.trip_id
  WHERE t.line_id = p_line_id
    AND t.status = 'completed'
    AND t.id = (
      SELECT id
      FROM public.sehirici_trips
      WHERE line_id = p_line_id AND status = 'completed'
      ORDER BY started_at DESC NULLS LAST
      LIMIT 1
    )
  ORDER BY tl.recorded_at ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_sehirici_latest_completed_trip_path(UUID)
  TO authenticated;

COMMENT ON FUNCTION public.get_sehirici_latest_completed_trip_path(UUID) IS
  'Bir hattın en son tamamlanmış seferinin tüm GPS noktalarını zaman sırasına '
  'göre döner. Admin draw aracı "Son Seferden Öner" akışı için kullanır.';
