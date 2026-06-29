-- AD5 — Feature flags, app config, analytics
-- See .superpowers/sdd/task-ad5-brief.md

CREATE TABLE IF NOT EXISTS feature_flags (
  key text PRIMARY KEY,
  value jsonb NOT NULL DEFAULT 'true',
  description text,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES staff(id)
);

CREATE TABLE IF NOT EXISTS app_config (
  key text PRIMARY KEY,
  value jsonb NOT NULL,
  description text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES staff(id)
);

-- Seed basico
INSERT INTO app_config (key, value, description) VALUES
  ('min_android_version', '"1.0.0"', 'Minimum required Android version'),
  ('min_ios_version', '"1.0.0"', 'Minimum required iOS version'),
  ('maintenance_mode', 'false', 'Global maintenance mode flag'),
  ('force_update_title', '"Update Required"', 'Force update dialog title'),
  ('force_update_message', '"Please update to the latest version to continue."', 'Force update dialog message')
ON CONFLICT (key) DO NOTHING;

INSERT INTO feature_flags (key, value, description) VALUES
  ('chat_enabled', 'true', 'Enable/disable chat feature'),
  ('grid_nearby_enabled', 'true', 'Enable the nearby grid'),
  ('albums_enabled', 'true', 'Enable private albums'),
  ('registration_open', 'true', 'Allow new user registration')
ON CONFLICT (key) DO NOTHING;

-- Permisos AD5
INSERT INTO role_permissions (role, permission, requires_justification) VALUES
  ('admin',      'flags.read',   false),
  ('admin',      'flags.write',  true),
  ('admin',      'config.read',  false),
  ('admin',      'config.write', true),
  ('superadmin', 'flags.read',   false),
  ('superadmin', 'flags.write',  true),
  ('superadmin', 'config.read',  false),
  ('superadmin', 'config.write', true)
ON CONFLICT (role, permission) DO NOTHING;
