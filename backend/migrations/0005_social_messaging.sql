CREATE TABLE taps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('looking','hot','friendly')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_taps_to ON taps(to_user, created_at);

CREATE TABLE favorites (
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  target_id uuid REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, target_id)
);

CREATE TABLE blocks (
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  target_id uuid REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, target_id)
);

CREATE TABLE profile_views (
  viewer_id uuid REFERENCES users(id) ON DELETE CASCADE,
  target_id uuid REFERENCES users(id) ON DELETE CASCADE,
  viewed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (viewer_id, target_id)
);
CREATE INDEX idx_profile_views_target ON profile_views(target_id, viewed_at);

CREATE TABLE conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_message_at timestamptz
);

CREATE TABLE conversation_members (
  conversation_id uuid REFERENCES conversations(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  last_read_at timestamptz,
  muted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX idx_conv_members_user ON conversation_members(user_id);

CREATE TABLE messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('text','photo','ephemeral_photo','audio','location','album_share')),
  body text,
  media_key text,
  expires_after_view boolean NOT NULL DEFAULT false,
  view_seconds int,
  viewed_at timestamptz,
  unsent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_messages_conv ON messages(conversation_id, created_at);
