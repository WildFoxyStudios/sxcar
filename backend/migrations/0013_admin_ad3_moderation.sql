-- AD3: Moderation reports queue, photo moderation, CSAM queue
-- See docs/superpowers/specs/task-ad3-brief.md

-- Añadir staff_id a moderation_actions (para staff moderators, no users)
ALTER TABLE moderation_actions ADD COLUMN IF NOT EXISTS staff_id uuid REFERENCES staff(id);

-- Añadir status a csam_hits
ALTER TABLE csam_hits ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending'
  CHECK (status IN ('pending','reviewed','reported','dismissed'));

-- Añadir review notes
ALTER TABLE csam_hits ADD COLUMN IF NOT EXISTS notes text;

-- Permisos AD3
INSERT INTO role_permissions (role, permission, requires_justification) VALUES
  ('moderator', 'reports.view',    false),
  ('moderator', 'reports.resolve', true),
  ('moderator', 'photos.moderate', true),
  ('admin',     'reports.view',    false),
  ('admin',     'reports.resolve', true),
  ('admin',     'photos.moderate', true),
  ('superadmin','reports.view',    false),
  ('superadmin','reports.resolve', true),
  ('superadmin','photos.moderate', true),
  ('admin',     'csam.view',       false),
  ('admin',     'csam.report',     true),
  ('superadmin','csam.view',       false),
  ('superadmin','csam.report',     true)
ON CONFLICT (role, permission) DO NOTHING;
