-- 0032_profile_privacy_flags.sql
-- Phase 4 (E3): Add 6 granular privacy flags to profiles so users can hide
-- specific fields (role, tribes, position, ethnicity, relationship_status,
-- social_links) from public GET /profile/:id. All default TRUE = no behavior
-- change for existing users. Wired into get_by_id in T4.2 code changes.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS show_role               boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_tribes             boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_position           boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_ethnicity          boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_relationship_status boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_social_links       boolean NOT NULL DEFAULT true;