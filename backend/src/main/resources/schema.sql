-- PostgreSQL Schema Initialization for Ludo World Free (Google Cloud SQL)

-- 1. User Accounts Table
CREATE TABLE IF NOT EXISTS user_accounts (
    id UUID PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255),
    auth_provider VARCHAR(50),
    provider_id VARCHAR(255),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Player Profiles Table
CREATE TABLE IF NOT EXISTS player_profiles (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL UNIQUE,
    display_name VARCHAR(100) NOT NULL,
    avatar_url VARCHAR(255),
    country VARCHAR(100),
    country_flag VARCHAR(10),
    auth_provider VARCHAR(50),
    provider_id VARCHAR(255),
    preferred_game_type VARCHAR(50) DEFAULT 'CLASSIC',
    most_played_game_type VARCHAR(50) DEFAULT 'CLASSIC',
    classic_play_count INT DEFAULT 0,
    quick_play_count INT DEFAULT 0,
    team_up_play_count INT DEFAULT 0,
    computer_play_count INT DEFAULT 0,
    pass_n_play_play_count INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. Player Wallets Table
CREATE TABLE IF NOT EXISTS player_wallets (
    id UUID PRIMARY KEY,
    player_id UUID NOT NULL UNIQUE,
    balance BIGINT NOT NULL DEFAULT 2000,
    diamonds BIGINT NOT NULL DEFAULT 100,
    version BIGINT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Gold Transactions Table
CREATE TABLE IF NOT EXISTS gold_transactions (
    id UUID PRIMARY KEY,
    player_id UUID NOT NULL,
    transaction_type VARCHAR(50) NOT NULL,
    amount BIGINT NOT NULL,
    balance_before BIGINT NOT NULL,
    balance_after BIGINT NOT NULL,
    reference_id VARCHAR(255),
    source VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. Reward Events Table (AdMob Idempotency)
CREATE TABLE IF NOT EXISTS reward_events (
    id UUID PRIMARY KEY,
    provider VARCHAR(50) NOT NULL,
    provider_reward_id VARCHAR(255) NOT NULL,
    player_id UUID NOT NULL,
    reward_type VARCHAR(50) NOT NULL,
    amount BIGINT NOT NULL,
    status VARCHAR(50) NOT NULL,
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_provider_reward UNIQUE (provider, provider_reward_id)
);

-- 6. Friendships Table
CREATE TABLE IF NOT EXISTS friendships (
    id UUID PRIMARY KEY,
    requester_id UUID NOT NULL,
    addressee_id UUID NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_requester_addressee UNIQUE (requester_id, addressee_id)
);

CREATE TABLE IF NOT EXISTS buddy_game_invites (
    id UUID PRIMARY KEY,
    requester_id UUID NOT NULL,
    target_id UUID NOT NULL,
    entry_fee BIGINT NOT NULL,
    requester_session_id VARCHAR(64) NOT NULL,
    requester_color VARCHAR(8) NOT NULL,
    game_mode VARCHAR(16) NOT NULL DEFAULT 'CLASSIC',
    target_session_id VARCHAR(64),
    target_color VARCHAR(8),
    room_id VARCHAR(64),
    decline_reason VARCHAR(500),
    status VARCHAR(16) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_buddy_game_invites_target_status_expiry
    ON buddy_game_invites (target_id, status, expires_at);

CREATE INDEX IF NOT EXISTS idx_buddy_game_invites_requester_created
    ON buddy_game_invites (requester_id, created_at DESC);

-- Scalable conversation chat. User identities and public profile data are
-- owned by user_accounts and player_profiles respectively.
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

-- 7. Chat Messages Table
CREATE TABLE IF NOT EXISTS chat_messages (
    id UUID PRIMARY KEY,
    sender_id UUID NOT NULL,
    recipient_id UUID,
    room_id VARCHAR(255),
    content VARCHAR(1000) NOT NULL,
    message_type VARCHAR(50) NOT NULL DEFAULT 'TEXT',
    read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_chat_conversation_sender_recipient_created
    ON chat_messages (sender_id, recipient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_conversation_recipient_sender_created
    ON chat_messages (recipient_id, sender_id, created_at DESC);

-- 8. Voice Chat Sessions Table
CREATE TABLE IF NOT EXISTS voice_chat_sessions (
    id UUID PRIMARY KEY,
    channel_name VARCHAR(255) NOT NULL,
    player_id UUID NOT NULL,
    token VARCHAR(1000) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE
);

-- 9. Daily Goals and Idempotent Progress Events
CREATE TABLE IF NOT EXISTS daily_goals (
    id UUID PRIMARY KEY,
    player_id UUID NOT NULL,
    goal_date DATE NOT NULL,
    goal_type VARCHAR(40) NOT NULL,
    progress INT NOT NULL DEFAULT 0,
    target INT NOT NULL,
    reward_amount BIGINT NOT NULL,
    claimed BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT uk_daily_goal_player_date_type UNIQUE (player_id, goal_date, goal_type)
);

CREATE TABLE IF NOT EXISTS daily_goal_events (
    id UUID PRIMARY KEY,
    player_id UUID NOT NULL,
    event_id VARCHAR(160) NOT NULL,
    event_type VARCHAR(40) NOT NULL,
    game_id VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_daily_goal_event_player_event UNIQUE (player_id, event_id)
);

-- 10. Shared matchmaking queue and online game rooms (Cloud Run instances)
CREATE TABLE IF NOT EXISTS player_avatar_images (
    player_id UUID PRIMARY KEY,
    content_type VARCHAR(32) NOT NULL,
    image_data BYTEA NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS matchmaking_tickets (
    player_id UUID PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    avatar_url VARCHAR(500),
    country VARCHAR(100),
    country_flag VARCHAR(16),
    entry_fee BIGINT NOT NULL,
    player_count INTEGER NOT NULL DEFAULT 2,
    selected_color VARCHAR(8) NOT NULL DEFAULT 'red',
    game_mode VARCHAR(16) NOT NULL DEFAULT 'CLASSIC',
    queued_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_matchmaking_tickets_fee_queued
    ON matchmaking_tickets (entry_fee, queued_at);
CREATE INDEX IF NOT EXISTS idx_matchmaking_tickets_size_fee_queued
    ON matchmaking_tickets (player_count, entry_fee, game_mode, queued_at);

CREATE TABLE IF NOT EXISTS online_match_rooms (
    room_id VARCHAR(64) PRIMARY KEY,
    player_a_id UUID NOT NULL,
    player_a_name VARCHAR(100) NOT NULL,
    player_a_avatar VARCHAR(500),
    player_a_country VARCHAR(100),
    player_a_flag VARCHAR(16),
    player_b_id UUID NOT NULL,
    player_b_name VARCHAR(100) NOT NULL,
    player_b_avatar VARCHAR(500),
    player_b_country VARCHAR(100),
    player_b_flag VARCHAR(16),
    player_count INTEGER NOT NULL DEFAULT 2,
    game_mode VARCHAR(16) NOT NULL DEFAULT 'CLASSIC',
    player_a_color VARCHAR(8) NOT NULL DEFAULT 'red',
    player_b_color VARCHAR(8) NOT NULL DEFAULT 'yellow',
    player_c_id UUID,
    player_c_name VARCHAR(100),
    player_c_avatar VARCHAR(500),
    player_c_country VARCHAR(100),
    player_c_flag VARCHAR(16),
    player_c_color VARCHAR(8),
    player_d_id UUID,
    player_d_name VARCHAR(100),
    player_d_avatar VARCHAR(500),
    player_d_country VARCHAR(100),
    player_d_flag VARCHAR(16),
    player_d_color VARCHAR(8),
    entry_fee BIGINT NOT NULL,
    status VARCHAR(16) NOT NULL,
    player_a_connected BOOLEAN NOT NULL DEFAULT FALSE,
    player_b_connected BOOLEAN NOT NULL DEFAULT FALSE,
    player_c_connected BOOLEAN NOT NULL DEFAULT FALSE,
    player_d_connected BOOLEAN NOT NULL DEFAULT FALSE,
    turn_owner_id UUID,
    authoritative_roll_opportunity_id INTEGER NOT NULL DEFAULT 0,
    authoritative_roll_player_id UUID,
    authoritative_dice_value INTEGER,
    latest_state_json TEXT,
    latest_state_sender_id UUID,
    state_revision BIGINT NOT NULL DEFAULT 0,
    rematch_revision BIGINT NOT NULL DEFAULT 0,
    rematch_round_id UUID,
    rematch_requester_id UUID,
    rematch_status VARCHAR(16) NOT NULL DEFAULT 'NONE',
    rematch_accepted_player_ids TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_online_match_player_a_status
    ON online_match_rooms (player_a_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_online_match_player_b_status
    ON online_match_rooms (player_b_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_online_match_player_c_status
    ON online_match_rooms (player_c_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_online_match_player_d_status
    ON online_match_rooms (player_d_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS online_match_state_events (
    id UUID PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL,
    revision BIGINT NOT NULL,
    sender_id UUID NOT NULL,
    state_json TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_online_match_state_revision UNIQUE (room_id, revision)
);

CREATE INDEX IF NOT EXISTS idx_online_match_state_events_room_revision
    ON online_match_state_events (room_id, revision);

CREATE TABLE IF NOT EXISTS online_match_chat_events (
    id BIGSERIAL PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL,
    player_id UUID NOT NULL,
    message_text VARCHAR(200) NOT NULL,
    event_type VARCHAR(16) NOT NULL DEFAULT 'MESSAGE',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_online_match_chat_room_id
    ON online_match_chat_events (room_id, id);


