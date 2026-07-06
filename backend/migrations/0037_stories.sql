-- Stories: ephemeral photo/video with 24h expiry.
-- Part of G12 (Oleada 3).

CREATE TABLE IF NOT EXISTS stories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  media_key TEXT NOT NULL,
  media_type TEXT NOT NULL DEFAULT 'photo', -- 'photo' or 'video'
  caption TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_stories_user ON stories(user_id, created_at DESC);
-- Partial index on non-expired stories — now() is STABLE so we use a regular index instead.
-- The backend queries already add WHERE expires_at > now() in SQL.
CREATE INDEX IF NOT EXISTS idx_stories_expires ON stories(expires_at);

-- Story views: tracks who viewed which story.
CREATE TABLE IF NOT EXISTS story_views (
  story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_story_views_story ON story_views(story_id);
