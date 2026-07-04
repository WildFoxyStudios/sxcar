-- 0031_profile_details.sql
-- Phase 4 (E3): Add extensible details blob to profiles so edit_profile_screen
-- can persist Grindr-parity fields (vaccines, healthy practices, social handles,
-- trip counts, etc.) without requiring a migration per field.
--
-- The shape is owned by the Flutter client. Backend only stores/returns it.
-- App-layer validation in T4.2 enforces 8KB max + JSON-object-only.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS details jsonb NOT NULL DEFAULT '{}'::jsonb;
