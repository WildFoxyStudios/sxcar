-- 0030_privacy_preferences.sql
-- Phase 2 / E2 (Settings redesign): 7 new columns on profiles.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS multimedia_show_album_updates boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS multimedia_show_carousel     boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS chat_mark_chatted            boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS chat_sync                    boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS screen_keep_unlocked         boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS visitor_status               smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS units                        smallint NOT NULL DEFAULT 0;

-- visitor_status: 0=disabled, 1=enabled, 2=auto
-- units:          0=metric,   1=imperial
-- Both validated at the API layer (range checks in PUT handler).