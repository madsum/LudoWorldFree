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

-- 9. Daily Reward Progress Table
CREATE TABLE IF NOT EXISTS daily_reward_progress (
    id UUID PRIMARY KEY,
    player_id UUID NOT NULL UNIQUE,
    current_streak INT NOT NULL DEFAULT 0,
    last_claim_date DATE,
    last_claim_time TIMESTAMP WITH TIME ZONE,
    bonus_ad_claimed_today BOOLEAN NOT NULL DEFAULT FALSE,
    last_bonus_ad_claim_date DATE,
    version BIGINT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_daily_reward_player_id ON daily_reward_progress(player_id);
