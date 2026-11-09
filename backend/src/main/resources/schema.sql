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
CREATE TABLE IF NOT EXISTS matchmaking_tickets (
    player_id UUID PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    avatar_url VARCHAR(500),
    country VARCHAR(100),
    country_flag VARCHAR(16),
    entry_fee BIGINT NOT NULL,
    queued_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_matchmaking_tickets_fee_queued
    ON matchmaking_tickets (entry_fee, queued_at);

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
    entry_fee BIGINT NOT NULL,
    status VARCHAR(16) NOT NULL,
    player_a_connected BOOLEAN NOT NULL DEFAULT FALSE,
    player_b_connected BOOLEAN NOT NULL DEFAULT FALSE,
    turn_owner_id UUID,
    authoritative_roll_opportunity_id INTEGER NOT NULL DEFAULT 0,
    authoritative_roll_player_id UUID,
    authoritative_dice_value INTEGER,
    latest_state_json TEXT,
    latest_state_sender_id UUID,
    state_revision BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_online_match_player_a_status
    ON online_match_rooms (player_a_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_online_match_player_b_status
    ON online_match_rooms (player_b_id, status, created_at DESC);

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


