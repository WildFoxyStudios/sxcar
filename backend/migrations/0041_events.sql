CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  description TEXT,
  location_name TEXT NOT NULL,
  lat DOUBLE PRECISION NOT NULL,
  lon DOUBLE PRECISION NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ,
  max_attendees INT DEFAULT 0,  -- 0 = unlimited
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE event_attendees (
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'going',  -- going, maybe, not_going
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);

-- Index for nearby event queries (lat/lon btree for range scanning)
CREATE INDEX idx_events_lat ON events(lat);
CREATE INDEX idx_events_lon ON events(lon);
CREATE INDEX idx_events_creator ON events(creator_id);
CREATE INDEX idx_event_attendees_event ON event_attendees(event_id);
CREATE INDEX idx_event_attendees_user ON event_attendees(user_id);
CREATE INDEX idx_events_starts_at ON events(starts_at);
