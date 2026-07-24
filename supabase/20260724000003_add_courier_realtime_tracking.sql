-- Enable real-time tracking for courier location updates
-- This ensures courier_requests table broadcasts location updates to clients

-- Add realtime broadcasts for courier_requests if not already enabled
-- (If already exists, skip - it's safe to run idempotently)
DO $$
BEGIN
  -- Try to add courier_requests, ignore if already exists
  EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE courier_requests';
EXCEPTION WHEN duplicate_object THEN
  NULL;
END;
$$;

-- Ensure profiles has realtime enabled for location tracking
DO $$
BEGIN
  EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE profiles';
EXCEPTION WHEN duplicate_object THEN
  NULL;
END;
$$;

-- Create an index for efficient courier lookups in package tracking
CREATE INDEX IF NOT EXISTS idx_courier_requests_courier_id_status
  ON courier_requests(courier_id, status)
  WHERE courier_id IS NOT NULL;

-- Add a trigger to update last_location_update when courier location changes
CREATE OR REPLACE FUNCTION update_courier_location_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.last_location_update = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_courier_location_timestamp ON profiles;
CREATE TRIGGER trigger_update_courier_location_timestamp
BEFORE UPDATE OF last_known_lat, last_known_lng ON profiles
FOR EACH ROW
EXECUTE FUNCTION update_courier_location_timestamp();

-- Comment for documentation
COMMENT ON TABLE courier_requests IS 'User package delivery requests with location tracking for real-time courier tracking';
COMMENT ON COLUMN courier_requests.courier_id IS 'Assigned courier for this delivery request';
COMMENT ON COLUMN courier_requests.pickup_lat IS 'Pickup location latitude';
COMMENT ON COLUMN courier_requests.pickup_lng IS 'Pickup location longitude';
COMMENT ON COLUMN courier_requests.delivery_lat IS 'Delivery location latitude';
COMMENT ON COLUMN courier_requests.delivery_lng IS 'Delivery location longitude';

DO $$ BEGIN
  RAISE NOTICE '✅ 20260724000003 — Courier real-time tracking configured';
END $$;
