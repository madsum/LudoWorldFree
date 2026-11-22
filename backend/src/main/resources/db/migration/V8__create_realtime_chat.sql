CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY,
    conversation_type VARCHAR(12) NOT NULL CHECK (conversation_type IN ('DIRECT', 'GROUP')),
    direct_key VARCHAR(80) UNIQUE,
    title VARCHAR(120),
    created_by UUID NOT NULL REFERENCES user_accounts(id),
    last_sequence BIGINT NOT NULL DEFAULT 0 CHECK (last_sequence >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK ((conversation_type = 'DIRECT' AND direct_key IS NOT NULL)
        OR (conversation_type = 'GROUP' AND direct_key IS NULL))
);

CREATE TABLE IF NOT EXISTS conversation_participants (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    role VARCHAR(12) NOT NULL DEFAULT 'MEMBER' CHECK (role IN ('OWNER', 'ADMIN', 'MEMBER')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_read_sequence BIGINT NOT NULL DEFAULT 0,
    muted_until TIMESTAMPTZ,
    PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user
    ON conversation_participants (user_id, conversation_id);

CREATE TABLE IF NOT EXISTS messages (
    conversation_id UUID NOT NULL,
    sequence BIGINT NOT NULL,
    id UUID NOT NULL,
    sender_id UUID NOT NULL REFERENCES user_accounts(id),
    client_message_id UUID NOT NULL,
    body TEXT,
    ciphertext TEXT,
    encrypted BOOLEAN NOT NULL DEFAULT FALSE,
    content_type VARCHAR(24) NOT NULL DEFAULT 'TEXT',
    attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
    reply_to_sequence BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (conversation_id, sequence),
    UNIQUE (conversation_id, sender_id, client_message_id),
    UNIQUE (conversation_id, id),
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
    FOREIGN KEY (conversation_id, sender_id)
        REFERENCES conversation_participants(conversation_id, user_id),
    FOREIGN KEY (conversation_id, reply_to_sequence)
        REFERENCES messages(conversation_id, sequence),
    CHECK ((encrypted AND ciphertext IS NOT NULL AND body IS NULL)
        OR (NOT encrypted AND body IS NOT NULL AND ciphertext IS NULL)),
    CHECK (content_type IN ('TEXT', 'IMAGE', 'AUDIO', 'MIXED'))
) PARTITION BY HASH (conversation_id);

DO $$
DECLARE partition_index INTEGER;
BEGIN
    FOR partition_index IN 0..15 LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS messages_p%s PARTITION OF messages '
            'FOR VALUES WITH (MODULUS 16, REMAINDER %s)',
            partition_index, partition_index);
    END LOOP;
END $$;

CREATE INDEX IF NOT EXISTS idx_messages_conversation_order
    ON messages (conversation_id, sequence DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender_time
    ON messages (sender_id, created_at DESC);

CREATE TABLE IF NOT EXISTS message_receipts (
    conversation_id UUID NOT NULL,
    sequence BIGINT NOT NULL,
    user_id UUID NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    PRIMARY KEY (conversation_id, sequence, user_id),
    FOREIGN KEY (conversation_id, sequence)
        REFERENCES messages(conversation_id, sequence) ON DELETE CASCADE,
    FOREIGN KEY (conversation_id, user_id)
        REFERENCES conversation_participants(conversation_id, user_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_message_receipts_user_unread
    ON message_receipts (user_id, conversation_id, sequence)
    WHERE read_at IS NULL;

CREATE TABLE IF NOT EXISTS chat_outbox (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMPTZ,
    attempts INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_chat_outbox_unpublished
    ON chat_outbox (id) WHERE published_at IS NULL;

CREATE TABLE IF NOT EXISTS chat_presence (
    user_id UUID PRIMARY KEY REFERENCES user_accounts(id) ON DELETE CASCADE,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS chat_media_uploads (
    id UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    owner_id UUID NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    object_key VARCHAR(512) NOT NULL UNIQUE,
    content_type VARCHAR(100) NOT NULL,
    byte_size BIGINT NOT NULL CHECK (byte_size > 0),
    sha256_hex CHAR(64) NOT NULL,
    state VARCHAR(12) NOT NULL DEFAULT 'PENDING'
        CHECK (state IN ('PENDING', 'ATTACHED', 'EXPIRED')),
    expires_at TIMESTAMPTZ NOT NULL,
    attached_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_chat_media_owner_state
    ON chat_media_uploads (owner_id, conversation_id, state, expires_at);

-- Public E2EE key material only; private identity/session keys stay on devices.
CREATE TABLE IF NOT EXISTS chat_device_key_bundles (
    user_id UUID NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    device_id VARCHAR(120) NOT NULL,
    identity_key TEXT NOT NULL,
    signed_prekey TEXT NOT NULL,
    signed_prekey_signature TEXT NOT NULL,
    one_time_prekeys JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, device_id)
);
