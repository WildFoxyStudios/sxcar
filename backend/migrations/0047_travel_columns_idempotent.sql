-- Ensure the Travel Pass columns exist on the users table.
--
-- These columns were originally added by 0040_travel_pass.sql, but the
-- set_travel handler ALSO ran the same ALTER TABLE at runtime on every
-- POST /me/travel request (taking an ACCESS EXCLUSIVE lock on users each
-- call — a self-inflicted DoS under concurrency). That runtime ALTER has
-- been removed; this migration guarantees the columns exist so the handler's
-- UPDATE keeps working, both on the live DB (already has them) and in tests.
--
-- Purely additive and idempotent: IF NOT EXISTS makes it a no-op wherever
-- the columns already exist. Column names/types/nullability match exactly
-- what the removed runtime ALTER (and 0040) created.

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
