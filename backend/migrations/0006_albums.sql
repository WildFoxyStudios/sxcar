CREATE TABLE albums (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_albums_owner ON albums(owner_id);

CREATE TABLE album_photos (
  album_id uuid REFERENCES albums(id) ON DELETE CASCADE,
  photo_id uuid REFERENCES photos(id) ON DELETE CASCADE,
  position int NOT NULL DEFAULT 0,
  PRIMARY KEY (album_id, photo_id)
);

CREATE TABLE album_shares (
  album_id uuid REFERENCES albums(id) ON DELETE CASCADE,
  shared_with_user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  expires_at timestamptz,
  PRIMARY KEY (album_id, shared_with_user_id)
);
CREATE INDEX idx_album_shares_user ON album_shares(shared_with_user_id);
