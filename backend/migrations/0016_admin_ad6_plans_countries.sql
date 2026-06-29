-- AD6 — Planes free/premium configurables + administración por país
-- See .superpowers/sdd/task-ad6-brief.md

CREATE TABLE IF NOT EXISTS plans (
  code text PRIMARY KEY,
  name text NOT NULL,
  tier int NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS plan_features (
  plan_code text NOT NULL REFERENCES plans(code) ON DELETE CASCADE,
  feature text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  limit_value int,
  PRIMARY KEY (plan_code, feature)
);

CREATE TABLE IF NOT EXISTS plan_prices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_code text NOT NULL REFERENCES plans(code) ON DELETE CASCADE,
  country_code text NOT NULL DEFAULT 'XX',
  currency text NOT NULL DEFAULT 'USD',
  price_monthly numeric(10,2),
  price_yearly numeric(10,2),
  revenuecat_product_id text,
  UNIQUE (plan_code, country_code)
);

CREATE TABLE IF NOT EXISTS country_config (
  country_code text PRIMARY KEY,
  name text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  disabled_features text[] NOT NULL DEFAULT '{}',
  min_age int NOT NULL DEFAULT 18,
  requires_explicit_consent boolean NOT NULL DEFAULT false,
  data_retention_days int,
  force_discreet_mode boolean NOT NULL DEFAULT false,
  hide_sensitive_fields boolean NOT NULL DEFAULT false,
  hide_distance boolean NOT NULL DEFAULT false,
  geo_restricted boolean NOT NULL DEFAULT false,
  restricted_features text[] NOT NULL DEFAULT '{}',
  travel_warning text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Seed plan free (obligatorio)
INSERT INTO plans (code, name, tier, description) VALUES
  ('free', 'Free', 0, 'Basic free tier with ads')
ON CONFLICT (code) DO NOTHING;

INSERT INTO plan_features (plan_code, feature, enabled) VALUES
  ('free', 'basic_grid', true),
  ('free', 'basic_chat', true),
  ('free', 'one_photo', true)
ON CONFLICT (plan_code, feature) DO NOTHING;

INSERT INTO plan_prices (plan_code, country_code, currency, price_monthly, price_yearly) VALUES
  ('free', 'XX', 'USD', 0, 0)
ON CONFLICT (plan_code, country_code) DO NOTHING;

-- Seed country default (global fallback)
INSERT INTO country_config (country_code, name) VALUES
  ('XX', 'Global (Default)')
ON CONFLICT (country_code) DO NOTHING;

-- Permisos AD6
INSERT INTO role_permissions (role, permission, requires_justification) VALUES
  ('admin',      'plans.read',    false),
  ('admin',      'plans.write',   true),
  ('admin',      'countries.read', false),
  ('admin',      'countries.write', true),
  ('superadmin', 'plans.read',    false),
  ('superadmin', 'plans.write',   true),
  ('superadmin', 'countries.read', false),
  ('superadmin', 'countries.write', true)
ON CONFLICT (role, permission) DO NOTHING;
