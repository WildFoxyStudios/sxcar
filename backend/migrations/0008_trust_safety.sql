CREATE TABLE reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_kind text NOT NULL CHECK (target_kind IN ('profile','photo','message')),
  target_id uuid,
  reason text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','reviewing','actioned','dismissed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);
CREATE INDEX idx_reports_status ON reports(status);

CREATE TABLE moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moderator_id uuid REFERENCES users(id) ON DELETE SET NULL,
  target_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action text NOT NULL CHECK (action IN ('warn','suspend','ban','clear')),
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_moderation_target ON moderation_actions(target_user_id);

CREATE TABLE csam_hits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photo_id uuid,
  source text,
  hash text,
  matched_at timestamptz NOT NULL DEFAULT now(),
  reported_to_authority_at timestamptz
);

CREATE TABLE audit_log (
  id bigserial PRIMARY KEY,
  actor_id uuid,
  action text,
  target text,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_created ON audit_log(created_at);
