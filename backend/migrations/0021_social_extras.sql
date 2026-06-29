-- Add tap_type column to taps table, then drop old type column
ALTER TABLE taps ADD COLUMN IF NOT EXISTS tap_type text NOT NULL DEFAULT 'fire' CHECK (tap_type IN ('fire','wave','smile','hello'));
ALTER TABLE taps DROP COLUMN IF EXISTS type;

-- Add reason column to blocks table
ALTER TABLE blocks ADD COLUMN IF NOT EXISTS reason text;
