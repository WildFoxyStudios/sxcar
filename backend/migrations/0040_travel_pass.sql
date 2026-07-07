-- Travel Pass: virtual location override for users to explore other cities.
-- Columns added directly to the users table for simplicity (no new table).

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS travel_lat DOUBLE PRECISION NULL,
  ADD COLUMN IF NOT EXISTS travel_lon DOUBLE PRECISION NULL,
  ADD COLUMN IF NOT EXISTS travel_city_name TEXT NULL,
  ADD COLUMN IF NOT EXISTS travel_expires_at TIMESTAMPTZ NULL;

-- Down migration:
-- ALTER TABLE users
--   DROP COLUMN IF EXISTS travel_expires_at,
--   DROP COLUMN IF EXISTS travel_city_name,
--   DROP COLUMN IF EXISTS travel_lon,
--   DROP COLUMN IF EXISTS travel_lat;
