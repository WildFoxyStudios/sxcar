CREATE TABLE locations (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  geog geography(Point,4326) NOT NULL,
  accuracy_m double precision,
  show_distance boolean NOT NULL DEFAULT true,
  is_incognito boolean NOT NULL DEFAULT false,
  roam_geog geography(Point,4326),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_locations_geog ON locations USING GIST (geog);
CREATE INDEX idx_locations_roam ON locations USING GIST (roam_geog);
CREATE TRIGGER locations_set_updated_at BEFORE UPDATE ON locations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE safety_zones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  geog geography(Point,4326) NOT NULL,
  radius_m double precision NOT NULL,
  action text NOT NULL CHECK (action IN ('hide_distance','hide_profile')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_safety_zones_user ON safety_zones(user_id);
