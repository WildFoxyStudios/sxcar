-- Add notification_prefs JSONB column to profiles for push notification preferences.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS notification_prefs JSONB
  DEFAULT '{"new_messages": true, "new_taps": true, "promotions": false}'::jsonb;
