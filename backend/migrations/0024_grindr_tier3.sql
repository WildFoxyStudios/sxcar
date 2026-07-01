-- Grindr parity Tier 3: Right Now, sessions, screenshot alerts, idle reminders
-- 0024_grindr_tier3.sql

-- Right Now: a feed of intents (Grindr's "Right Now" feature)
-- Users post an intent (e.g. "Looking for coffee, Right Now at 4pm") to nearby users
CREATE TABLE IF NOT EXISTS right_now_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_right_now_active ON right_now_intents(expires_at);
CREATE INDEX IF NOT EXISTS idx_right_now_user ON right_now_intents(user_id);

-- Multiple instances: user can be logged in on N devices
-- Existing refresh_tokens (F0.2) already supports this — we just need an endpoint to list active sessions
-- (relies on refresh_tokens table that already exists; no schema change needed)

-- Screenshot alert: log when a user takes a screenshot of chat (best-effort detection)
-- We can't really detect screenshots on the server; this is a client-side flag
-- Server stores: when a user reports a screenshot of their chat, it logs an alert
CREATE TABLE IF NOT EXISTS screenshot_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  reported_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_screenshot_alerts_conv ON screenshot_alerts(conversation_id);

-- Friendly reminder: an auto-message sent if user is idle in chat
-- We store the configured delay per user (default 24h)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS idle_reminder_hours int;

-- Add Tier 3 permissions to role_permissions
INSERT INTO role_permissions (role, permission, requires_justification) VALUES
  ('admin', 'tier3.view', false),
  ('admin', 'tier3.moderate', true),
  ('superadmin', 'tier3.view', false),
  ('superadmin', 'tier3.moderate', true)
ON CONFLICT (role, permission) DO NOTHING;
