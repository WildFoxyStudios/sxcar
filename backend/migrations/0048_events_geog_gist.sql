-- 0048: Add a geography(Point,4326) column + GiST index to events.
--
-- The events table stores location as separate lat/lon DOUBLE PRECISION
-- columns, so ST_DWithin on ST_MakePoint(lon,lat)::geography cannot use any
-- spatial index — every nearby query degrades to a full-table scan computing
-- ST_DWithin per row. This migration adds a generated `geog` column and a
-- GiST index so future query optimizations can use it.
--
-- This migration is additive + idempotent:
--   * adds the column only if it doesn't exist
--   * backfills NULL geog rows from existing lat/lon
--   * creates the GiST index if absent
-- It does NOT change the existing lat/lon columns or the current query shape
-- (those keep working unchanged). A follow-up should rewrite the events
-- ST_DWithin/ST_Distance expressions to use `e.geog` directly.

ALTER TABLE events ADD COLUMN IF NOT EXISTS geog geography(Point, 4326);

UPDATE events
   SET geog = ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography
 WHERE geog IS NULL
   AND lat IS NOT NULL
   AND lon IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_events_geog ON events USING GIST (geog);
