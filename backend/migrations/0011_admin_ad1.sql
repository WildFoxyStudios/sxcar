-- Admin Panel AD1 — Skeleton (staff identity + RBAC + 2FA + audit).
-- See docs/superpowers/specs/2026-06-28-admin-ad1-skeleton-design.md.
--
-- Principios (sellados en spec §1, no se revierten sin ADR):
--   * Identidad separada: tabla `staff` NO `users`. Atacante con credenciales
--     de usuario NO puede ser staff aunque manipule su rol.
--   * 2FA obligatorio: TOTP cifrado en reposo (AES-256-GCM, KEK rotable).
--   * audit_log append-only via triggers PG (no se fía de disciplina de código).
--   * Sesiones cortas (8h) y revocables, separadas de refresh_tokens de users.
--   * Sin "permisos fantasma": el seed de role_permissions SOLO lista
--     permisos que los endpoints de AD1 ejercitan. Nuevos permisos llegan
--     en el PR que introduce su endpoint.

-- ---------------------------------------------------------------------------
-- staff — identidad staff SEPARADA de users.
-- ---------------------------------------------------------------------------
CREATE TABLE staff (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email               citext UNIQUE NOT NULL,
  password_hash       text NOT NULL,                  -- argon2id (m=64MB,t=3,p=1)
  totp_secret_enc     bytea NOT NULL,                 -- AES-256-GCM(plaintext + 12B nonce + 16B tag)
  totp_enabled_at     timestamptz NOT NULL,           -- cuando se activo TOTP
  recovery_codes_hash text[] NOT NULL,                -- 10 hashes argon2id, single-use
  role                text NOT NULL CHECK (role IN ('support','moderator','admin','superadmin')),
  status              text NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active','suspended','disabled')),
  last_login_at       timestamptz,
  last_login_ip       inet,
  failed_login_count  integer NOT NULL DEFAULT 0,
  locked_until        timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid REFERENCES staff(id)       -- NULL si bootstrap inicial
);

-- Reusa la funcion set_updated_at() que ya existe (0001_extensions.sql).
CREATE TRIGGER trg_staff_updated_at
  BEFORE UPDATE ON staff
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Busquedas tipicas: por email (login) y por status (listado de staff no-activos).
CREATE INDEX idx_staff_email_lower ON staff (lower(email));
CREATE INDEX idx_staff_status_nonactive ON staff (status) WHERE status <> 'active';

-- ---------------------------------------------------------------------------
-- role_permissions — matriz rol → permisos (RBAC minimo-privilegio).
-- Una acción chequea permisos, NO roles. Mas granular, mas testeable.
-- ---------------------------------------------------------------------------
CREATE TABLE role_permissions (
  role                  text NOT NULL,
  permission            text NOT NULL,
  requires_justification boolean NOT NULL DEFAULT false,
  PRIMARY KEY (role, permission)
);

-- Seed AD1: SOLO permisos ejercitados por endpoints existentes en este PR.
-- (user.ban, media.takedown, report.resolve, refund.issue, flag.toggle,
--  staff.manage (excepto superadmin que SI lo tiene), legal.export,
--  dsar.delete, etc. llegan en AD2+ cuando entren sus endpoints.)
INSERT INTO role_permissions (role, permission, requires_justification) VALUES
  -- support
  ('support',     'admin.auth.login', false),
  ('support',     'admin.auth.2fa',   false),
  ('support',     'user.view',        false),
  -- moderator (mismos permisos que support por ahora; capabilities reales en AD3)
  ('moderator',   'admin.auth.login', false),
  ('moderator',   'admin.auth.2fa',   false),
  ('moderator',   'user.view',        false),
  -- admin
  ('admin',       'admin.auth.login', false),
  ('admin',       'admin.auth.2fa',   false),
  ('admin',       'user.view',        false),
  -- superadmin: incluye autogestión (con justificación obligatoria)
  ('superadmin',  'admin.auth.login', false),
  ('superadmin',  'admin.auth.2fa',   false),
  ('superadmin',  'user.view',        false),
  ('superadmin',  'staff.manage',     true),
  ('superadmin',  'audit.read',       false);

-- ---------------------------------------------------------------------------
-- staff_sessions — sesiones revocables, separadas de refresh_tokens de users.
-- Vida corta (8h vs 30d de users) porque el panel es superficie de ataque.
-- ---------------------------------------------------------------------------
CREATE TABLE staff_sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id        uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  issued_at       timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  revoked_at      timestamptz,
  revoked_reason  text,                              -- 'logout' | 'superadmin_revoke' | 'idle_timeout'
  ip              inet,
  user_agent      text,
  last_seen_at    timestamptz NOT NULL DEFAULT now()
);

-- Lookup rapido de sesiones activas por staff_id (chequeo en cada request).
CREATE INDEX idx_staff_sessions_active
  ON staff_sessions (staff_id) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- audit_log (existente, F0.2 0008_trust_safety.sql) — añadir columnas staff.
-- ---------------------------------------------------------------------------
ALTER TABLE audit_log
  ADD COLUMN actor_staff_id     uuid REFERENCES staff(id),
  ADD COLUMN staff_session_id   uuid REFERENCES staff_sessions(id),
  ADD COLUMN justification      text,                 -- obligatorio en permisos requires_justification
  ADD COLUMN legal_basis        text;                 -- solo para legal.export (futuro AD4)

-- ---------------------------------------------------------------------------
-- audit_log append-only via triggers PG.
-- Confiamos en la BD, no en disciplina del código. T11 prueba esto con
-- UPDATE/DELETE attempt → exception.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_log_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only (% attempted)', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_log_no_update
  BEFORE UPDATE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION audit_log_immutable();

CREATE TRIGGER trg_audit_log_no_delete
  BEFORE DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION audit_log_immutable();

-- TRUNCATE tiene su propio evento (no cubierto por UPDATE/DELETE triggers).
-- STATEMENT-level porque TRUNCATE opera por tabla, no por fila.
CREATE TRIGGER trg_audit_log_no_truncate
  BEFORE TRUNCATE ON audit_log
  FOR EACH STATEMENT EXECUTE FUNCTION audit_log_immutable();

-- ---------------------------------------------------------------------------
-- Recordatorio de rollback (NO ejecutar salvo emergencia; la migracion es
-- destructiva porque tira triggers y columnas). Documentado aqui para que
-- el siguiente que piense en revertir sepa qué pasos dar:
--
--   DROP TRIGGER IF EXISTS trg_audit_log_no_update ON audit_log;
--   DROP TRIGGER IF EXISTS trg_audit_log_no_delete ON audit_log;
--   DROP FUNCTION IF EXISTS audit_log_immutable();
--   ALTER TABLE audit_log
--     DROP COLUMN legal_basis,
--     DROP COLUMN justification,
--     DROP COLUMN staff_session_id,
--     DROP COLUMN actor_staff_id;
--   DROP INDEX IF EXISTS idx_staff_sessions_active;
--   DROP TABLE staff_sessions;
--   DROP INDEX IF EXISTS idx_staff_status_nonactive;
--   DROP INDEX IF EXISTS idx_staff_email_lower;
--   DROP TRIGGER IF EXISTS trg_staff_updated_at ON staff;
--   DROP TABLE staff;
--   DROP TABLE role_permissions;
-- ---------------------------------------------------------------------------
