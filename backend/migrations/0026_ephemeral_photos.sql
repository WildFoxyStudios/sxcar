-- Grindr parity: ephemeral "view once" photos in chat.
-- kind='ephemeral_photo' already allowed by the messages_kind CHECK (0005).
-- Track when the recipient first viewed it so it can't be re-opened.
ALTER TABLE messages ADD COLUMN IF NOT EXISTS ephemeral_viewed_at timestamptz;
