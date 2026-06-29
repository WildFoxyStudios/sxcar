-- AD2: Nuevos permisos para administración de usuarios
-- Ver docs/superpowers/specs/task-ad2-db-brief.md

-- Añadir 'shadowbanned' al CHECK constraint de users.status
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_status_check;
ALTER TABLE users ADD CONSTRAINT users_status_check
  CHECK (status IN ('active','suspended','banned','deleted','shadowbanned'));

-- Permisos para AD2 (idempotente, ON CONFLICT DO NOTHING)
INSERT INTO role_permissions (role, permission, requires_justification) VALUES
  ('admin',       'user.ban',         true),
  ('admin',       'user.suspend',     true),
  ('admin',       'user.activate',    true),
  ('admin',       'user.force_logout',true),
  ('admin',       'audit.read',       false),
  ('superadmin',  'user.ban',         true),
  ('superadmin',  'user.suspend',     true),
  ('superadmin',  'user.activate',    true),
  ('superadmin',  'user.force_logout',true)
ON CONFLICT (role, permission) DO NOTHING;
