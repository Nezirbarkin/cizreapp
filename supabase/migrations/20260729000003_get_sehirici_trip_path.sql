-- =============================================================================
-- Şehiriçi: Seferin geçtiği yol — konum geçmişini dizi olarak döndür
-- Tarih: 2026-07-29
-- Amaç: Kullanıcı haritası, şoförün aktif seferde geçtiği noktaları
-- polyline olarak çizebilsin. Mevcut sehirici_trip_locations tablosu zaten
-- realtime publication'da; bu RPC ilk yükleme + reconnection senaryoları
-- için tek seferde tüm geçmişi dizi olarak verir.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_sehirici_trip_path(p_trip_id UUID)
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
  SELECT lat, lng, recorded_at
  FROM public.sehirici_trip_locations
  WHERE trip_id = p_trip_id
  ORDER BY recorded_at ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_sehirici_trip_path(UUID) TO authenticated, anon;

COMMENT ON FUNCTION public.get_sehirici_trip_path(UUID) IS
  'Aktif seferin şoförünün geçtiği tüm konum noktalarını zaman sırasına göre döndürür. Polyline çizimi için kullanılır.';
