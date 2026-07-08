-- Backfill for the multi-photo profile gallery.
-- Rows in `photos` created before the gallery feature defaulted to
-- position=0 and is_primary=false. Give each user's photos a stable
-- position order, promote one to primary, and sync profiles.profile_photo_key.

-- 1. Renumber positions per user by creation order (idempotent for new rows,
--    which are already appended in created_at order).
WITH ordered AS (
  SELECT id,
         ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at ASC) - 1 AS pos
  FROM photos
)
UPDATE photos p
SET position = o.pos
FROM ordered o
WHERE p.id = o.id AND p.position IS DISTINCT FROM o.pos;

-- 2. For users who have photos but none flagged primary, promote the first
--    (lowest position) photo to primary.
WITH firsts AS (
  SELECT DISTINCT ON (user_id) id
  FROM photos
  WHERE user_id NOT IN (SELECT user_id FROM photos WHERE is_primary = true)
  ORDER BY user_id, position ASC
)
UPDATE photos p
SET is_primary = true
FROM firsts f
WHERE p.id = f.id;

-- 3. Sync profiles.profile_photo_key to the primary photo when it is unset,
--    so grid/discover fallback and single-photo readers keep working.
UPDATE profiles pr
SET profile_photo_key = ph.r2_key
FROM photos ph
WHERE ph.user_id = pr.user_id
  AND ph.is_primary = true
  AND pr.profile_photo_key IS NULL;
