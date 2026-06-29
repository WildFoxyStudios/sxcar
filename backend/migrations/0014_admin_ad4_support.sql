-- AD4: Support + GDPR + LER (Legal Enforcement Response)
-- See docs/superpowers/specs/task-ad4-brief.md

-- access_events: historial de acceso (login/IP) para LER.
-- Retencion 180 dias; purgar con job programado (AD5+).
CREATE TABLE IF NOT EXISTS access_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event text NOT NULL CHECK (event IN ('login','refresh','logout')),
  ip inet,
  user_agent text,
  device_id uuid REFERENCES devices(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_access_events_user_ts ON access_events(user_id, created_at DESC);

-- legal_holds: usuarios bajo requerimiento legal (suspender borrado).
CREATE TABLE IF NOT EXISTS legal_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  placed_by uuid NOT NULL REFERENCES staff(id),
  reason text NOT NULL,
  reference text,
  placed_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  released_by uuid REFERENCES staff(id),
  release_reason text
);
CREATE INDEX IF NOT EXISTS idx_legal_holds_user ON legal_holds(user_id) WHERE released_at IS NULL;

-- Permisos AD4
INSERT INTO role_permissions (role, permission, requires_justification) VALUES
  ('admin',      'entitlements.view',   false),
  ('admin',      'entitlements.manage', true),
  ('admin',      'dsar.view',           false),
  ('admin',      'dsar.process',        true),
  ('admin',      'legal.export',        true),
  ('admin',      'legal.hold',          true),
  ('superadmin', 'entitlements.view',   false),
  ('superadmin', 'entitlements.manage', true),
  ('superadmin', 'dsar.view',           false),
  ('superadmin', 'dsar.process',        true),
  ('superadmin', 'legal.export',        true),
  ('superadmin', 'legal.hold',          true)
ON CONFLICT (role, permission) DO NOTHING;
