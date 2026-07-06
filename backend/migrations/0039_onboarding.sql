-- Onboarding wizard state for newly-registered users.
-- A user is "onboarding" from registration until they complete the wizard
-- (or force-skip it). Onboarding users are hidden from `/grid/nearby` for
-- everyone else; their own profile detail still works.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS onboarding_skipped_cards JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Partial index: most users complete onboarding quickly, so the index
-- only covers the "completed" subset (the ones the grid will scan).
CREATE INDEX IF NOT EXISTS idx_users_onboarding_completed
  ON users (onboarding_completed_at)
  WHERE onboarding_completed_at IS NOT NULL;

-- Down migration (for dev rollback):
-- DROP INDEX IF EXISTS idx_users_onboarding_completed;
-- ALTER TABLE users
--   DROP COLUMN IF EXISTS onboarding_skipped_cards,
--   DROP COLUMN IF EXISTS onboarding_completed_at;
