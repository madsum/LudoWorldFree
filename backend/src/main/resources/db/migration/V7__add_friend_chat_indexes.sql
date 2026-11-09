CREATE INDEX IF NOT EXISTS idx_chat_conversation_sender_recipient_created
    ON chat_messages (sender_id, recipient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_conversation_recipient_sender_created
    ON chat_messages (recipient_id, sender_id, created_at DESC);
