-- Grindr parity Tier 2: boosts, saved phrases, saved places, Roam location pref
-- 0023_grindr_tier2.sql

-- Boost: a user can boost themselves (paid feature flag)
CREATE TABLE IF NOT EXISTS boosts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  source text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'package', 'trial'))
);
CREATE INDEX IF NOT EXISTS idx_boosts_active ON boosts(user_id, expires_at);

-- Saved phrases (quick replies)
CREATE TABLE IF NOT EXISTS saved_phrases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phrase text NOT NULL,
  position int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_saved_phrases_user ON saved_phrases(user_id, position);

-- Saved Places (Roam locations)
CREATE TABLE IF NOT EXISTS saved_places (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_saved_places_user ON saved_places(user_id);

-- Roam state: user's currently-selected location
CREATE TABLE IF NOT EXISTS user_location_pref (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  place_name text,
  is_roam boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);