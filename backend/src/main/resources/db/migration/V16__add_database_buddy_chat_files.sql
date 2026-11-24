CREATE TABLE IF NOT EXISTS buddy_chat_attachments (
    id UUID PRIMARY KEY,
    sender_id UUID NOT NULL,
    recipient_id UUID NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    content_type VARCHAR(100) NOT NULL,
    byte_size BIGINT NOT NULL CHECK (byte_size > 0 AND byte_size <= 20971520),
    sha256_hex CHAR(64) NOT NULL,
    file_data BYTEA NOT NULL,
    message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_buddy_chat_attachments_message
    ON buddy_chat_attachments (message_id)
    WHERE message_id IS NOT NULL;
