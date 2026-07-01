-- Grindr parity Tier 1: media messages, online indicator, profile views, health
-- 0022_grindr_tier1.sql

-- Media message fields (idempotent: chat may be partially in place)
ALTER TABLE messages ADD COLUMN IF NOT EXISTS media_url text;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS media_type text;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS caption text;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS lat double precision;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS lon double precision;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS read_at timestamptz;

-- Add 'media_type' CHECK constraint if not present (only photo and location for now)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'messages_media_type_check'
  ) THEN
    ALTER TABLE messages
      ADD CONSTRAINT messages_media_type_check
      CHECK (media_type IS NULL OR media_type IN ('photo','location'));
  END IF;
END$$;

-- Profile views: keep existing table but add a serial id for ordering and recent list
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profile_views' AND column_name = 'id'
  ) THEN
    ALTER TABLE profile_views ADD COLUMN id uuid NOT NULL DEFAULT gen_random_uuid();
    ALTER TABLE profile_views DROP CONSTRAINT IF EXISTS profile_views_pkey;
    ALTER TABLE profile_views ADD CONSTRAINT profile_views_pkey PRIMARY KEY (id);
  END IF;
END$$;
CREATE INDEX IF NOT EXISTS idx_profile_views_target_recent
  ON profile_views(target_id, viewed_at DESC);

-- Online indicator / last seen on users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen_at);