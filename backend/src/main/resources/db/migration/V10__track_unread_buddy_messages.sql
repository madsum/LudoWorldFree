ALTER TABLE chat_messages
    ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;

-- Existing history was already visible before unread tracking was added.
UPDATE chat_messages
SET read_at = created_at
WHERE read_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_chat_messages_unread_recipient
    ON chat_messages (recipient_id, created_at)
    WHERE read_at IS NULL;
