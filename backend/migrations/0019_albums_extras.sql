ALTER TABLE albums ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE albums ADD COLUMN IF NOT EXISTS is_private boolean NOT NULL DEFAULT false;
