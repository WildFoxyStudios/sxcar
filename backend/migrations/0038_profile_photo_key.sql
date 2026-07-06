-- Add profile_photo_key (text R2 key) to profiles so we can generate
-- presigned URLs without needing a photos-table join.  The existing
-- profile_photo_id (uuid FK → photos) stays for backwards compat.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS profile_photo_key text;
