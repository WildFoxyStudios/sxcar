-- Allow audio media_type in messages (added for voice message support).
-- The messages.kind CHECK already allows 'audio' (from 0005). This migration
-- relaxes the media_type CHECK constraint to also accept 'audio' values.

DO $$
BEGIN
  -- Drop the old constraint and recreate with 'audio' added.
  ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_media_type_check;
  ALTER TABLE messages
    ADD CONSTRAINT messages_media_type_check
    CHECK (media_type IS NULL OR media_type IN ('photo','location','audio'));
END $$;
