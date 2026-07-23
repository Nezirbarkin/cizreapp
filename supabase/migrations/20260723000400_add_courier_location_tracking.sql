-- Add location tracking for couriers to display on map
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS last_known_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS last_known_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS last_location_update TIMESTAMPTZ DEFAULT NOW();

-- Index for efficient courier location queries
CREATE INDEX IF NOT EXISTS idx_profiles_courier_location
  ON profiles(role, last_known_lat, last_known_lng)
  WHERE role = 'courier' AND last_known_lat IS NOT NULL;

-- Comment for documentation
COMMENT ON COLUMN profiles.last_known_lat IS 'Last known latitude of courier for map display';
COMMENT ON COLUMN profiles.last_known_lng IS 'Last known longitude of courier for map display';
COMMENT ON COLUMN profiles.last_location_update IS 'Timestamp of last location update';
