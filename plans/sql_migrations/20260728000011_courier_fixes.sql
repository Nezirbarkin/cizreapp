-- =====================================================
-- DOSYA: supabase/migrations/20260728000011_courier_fixes.sql
-- AMAÇ: Courier RLS + location tracking
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. Courier requests RLS (courier_requests.user_id yok, sender_id var)
DROP POLICY IF EXISTS "Users can view own courier requests" ON courier_requests;
CREATE POLICY "Users can view own courier requests" ON courier_requests
  FOR SELECT TO authenticated
  USING (sender_id = auth.uid() OR courier_id = auth.uid());

DROP POLICY IF EXISTS "Couriers can update assigned requests" ON courier_requests;
CREATE POLICY "Couriers can update assigned requests" ON courier_requests
  FOR UPDATE TO authenticated
  USING (courier_id = auth.uid())
  WITH CHECK (courier_id = auth.uid());

-- 2. Location upsert (sadece son konum)
CREATE OR REPLACE FUNCTION upsert_courier_location(
  p_lat NUMERIC,
  p_lng NUMERIC,
  p_accuracy NUMERIC DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO courier_locations (courier_id, lat, lng, accuracy, updated_at)
  VALUES (auth.uid(), p_lat, p_lng, p_accuracy, NOW())
  ON CONFLICT (courier_id)
  DO UPDATE SET
    lat = EXCLUDED.lat,
    lng = EXCLUDED.lng,
    accuracy = EXCLUDED.accuracy,
    updated_at = NOW();
END;
$$;

REVOKE ALL ON FUNCTION upsert_courier_location(NUMERIC, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION upsert_courier_location(NUMERIC, NUMERIC, NUMERIC) TO authenticated;

-- 3. Eski location temizleme (24 saat) - courier_locations tablosu yok, atlanıyor
-- DELETE FROM courier_locations
-- WHERE updated_at < NOW() - INTERVAL '24 hours';

-- 4. Courier locations RLS - tablo yok, atlanıyor
-- ALTER TABLE courier_locations ENABLE ROW LEVEL SECURITY;
-- DROP POLICY IF EXISTS "Couriers can update own location" ON courier_locations;
-- CREATE POLICY "Couriers can update own location" ON courier_locations
--   FOR ALL TO authenticated
--   USING (courier_id = auth.uid())
--   WITH CHECK (courier_id = auth.uid());
-- DROP POLICY IF EXISTS "Users can view courier location for active requests" ON courier_locations;
-- CREATE POLICY "Users can view courier location for active requests" ON courier_locations
--   FOR SELECT TO authenticated
--   USING (
--     EXISTS (
--       SELECT 1 FROM courier_requests cr
--       WHERE cr.courier_id = courier_locations.courier_id
--         AND cr.sender_id = auth.uid()
--         AND cr.status IN ('assigned', 'picking_up', 'in_transit')
--     )
--   );
