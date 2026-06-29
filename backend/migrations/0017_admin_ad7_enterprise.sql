-- AD7 — Enterprise catalog: experiments, i18n, CMS, campaigns, abuse, API keys, webhooks, config rollback
-- See .superpowers/sdd/task-ad7-brief.md

-- Experiments / A-B testing
CREATE TABLE IF NOT EXISTS experiments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  name text NOT NULL,
  description text,
  variants jsonb NOT NULL DEFAULT '[]',
  enabled boolean NOT NULL DEFAULT false,
  start_at timestamptz,
  end_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- i18n translations (gestionables)
CREATE TABLE IF NOT EXISTS translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  locale text NOT NULL,
  key text NOT NULL,
  value text NOT NULL,
  UNIQUE (locale, key)
);

-- CMS content (banners, announcements, onboarding, legal doc versions)
CREATE TABLE IF NOT EXISTS cms_content (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  content_type text NOT NULL DEFAULT 'text' CHECK (content_type IN ('text','html','markdown','json')),
  title text,
  body text NOT NULL,
  locale text NOT NULL DEFAULT 'en',
  active boolean NOT NULL DEFAULT true,
  publish_at timestamptz,
  expire_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES staff(id)
);
CREATE INDEX IF NOT EXISTS idx_cms_key_locale ON cms_content(key, locale);

-- Legal document versions (tracking aceptación de TOS/Privacy)
CREATE TABLE IF NOT EXISTS legal_doc_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type text NOT NULL CHECK (doc_type IN ('tos','privacy','community_guidelines','cookie_policy')),
  version text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  published_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES staff(id)
);

-- Campaigns / broadcast messages
CREATE TABLE IF NOT EXISTS campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  campaign_type text NOT NULL CHECK (campaign_type IN ('push','email','in_app','all')),
  title text,
  body text NOT NULL,
  target_segment jsonb,
  scheduled_at timestamptz,
  sent_at timestamptz,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','scheduled','sending','sent','failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES staff(id)
);

-- Notification templates
CREATE TABLE IF NOT EXISTS notification_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  name text NOT NULL,
  channel text NOT NULL CHECK (channel IN ('push','email','in_app')),
  title_template text NOT NULL,
  body_template text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Anti-fraud / abuse rules engine (simplificado: reglas con umbrales)
CREATE TABLE IF NOT EXISTS abuse_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  rule_type text NOT NULL CHECK (rule_type IN ('velocity','pattern','threshold')),
  config jsonb NOT NULL,
  action text NOT NULL CHECK (action IN ('flag','suspend','ban','notify_staff')),
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- API keys (para partners/integraciones)
CREATE TABLE IF NOT EXISTS api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  key_hash text NOT NULL,
  key_prefix text NOT NULL,
  permissions text[] NOT NULL DEFAULT '{}',
  rate_limit_rps int NOT NULL DEFAULT 10,
  active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES staff(id),
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz
);

-- Webhook subscriptions
CREATE TABLE IF NOT EXISTS webhook_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  url text NOT NULL,
  events text[] NOT NULL,
  secret text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES staff(id)
);

-- Config versioning (rollback de toda la config editable)
CREATE TABLE IF NOT EXISTS config_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL,
  entity_key text NOT NULL,
  previous_value jsonb NOT NULL,
  new_value jsonb NOT NULL,
  changed_by uuid NOT NULL REFERENCES staff(id),
  rolled_back boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Permisos AD7
INSERT INTO role_permissions (role, permission, requires_justification) VALUES
  ('admin',      'experiments.read',  false),
  ('admin',      'experiments.write', true),
  ('admin',      'cms.read',          false),
  ('admin',      'cms.write',         true),
  ('admin',      'campaigns.read',    false),
  ('admin',      'campaigns.write',   true),
  ('admin',      'templates.read',    false),
  ('admin',      'templates.write',   true),
  ('admin',      'abuse.read',        false),
  ('admin',      'abuse.write',       true),
  ('admin',      'apikeys.read',      false),
  ('admin',      'apikeys.write',     true),
  ('admin',      'webhooks.read',     false),
  ('admin',      'webhooks.write',    true),
  ('admin',      'config.read',       false),
  ('admin',      'config.write',      true),
  ('superadmin','experiments.read',  false),
  ('superadmin','experiments.write', true),
  ('superadmin','cms.read',          false),
  ('superadmin','cms.write',         true),
  ('superadmin','campaigns.read',    false),
  ('superadmin','campaigns.write',   true),
  ('superadmin','templates.read',    false),
  ('superadmin','templates.write',   true),
  ('superadmin','abuse.read',        false),
  ('superadmin','abuse.write',       true),
  ('superadmin','apikeys.read',      false),
  ('superadmin','apikeys.write',     true),
  ('superadmin','webhooks.read',     false),
  ('superadmin','webhooks.write',    true),
  ('superadmin','config.read',       false),
  ('superadmin','config.write',      true)
ON CONFLICT (role, permission) DO NOTHING;
