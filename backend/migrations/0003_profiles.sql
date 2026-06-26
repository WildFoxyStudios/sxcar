CREATE TABLE profiles (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name text,
  about text,
  position text CHECK (position IN ('top','vers_top','versatile','vers_bottom','bottom','side')),
  body_type text,
  height_cm int,
  weight_kg int,
  relationship_status text,
  gender_identity text,
  pronouns text,
  hiv_status text,
  last_tested_on date,
  prep boolean,
  accept_nsfw boolean NOT NULL DEFAULT false,
  show_age boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE profile_tribes (
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  tribe text NOT NULL,
  PRIMARY KEY (user_id, tribe)
);
CREATE TABLE profile_looking_for (
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  intent text NOT NULL,
  PRIMARY KEY (user_id, intent)
);
CREATE TABLE profile_meet_at (
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  place text NOT NULL,
  PRIMARY KEY (user_id, place)
);
CREATE TABLE profile_tags (
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  tag citext NOT NULL,
  PRIMARY KEY (user_id, tag)
);
CREATE TABLE profile_ethnicities (
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  ethnicity text NOT NULL,
  PRIMARY KEY (user_id, ethnicity)
);

CREATE TABLE social_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind text NOT NULL,
  value text NOT NULL
);
CREATE INDEX idx_social_links_user ON social_links(user_id);

CREATE TABLE photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  r2_key text NOT NULL,
  blur_key text,
  position int NOT NULL DEFAULT 0,
  is_primary boolean NOT NULL DEFAULT false,
  is_nsfw boolean NOT NULL DEFAULT false,
  moderation_status text NOT NULL DEFAULT 'pending' CHECK (moderation_status IN ('pending','approved','rejected')),
  width int,
  height int,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_photos_user_pos ON photos(user_id, position);

CREATE TABLE verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('photo','id')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
