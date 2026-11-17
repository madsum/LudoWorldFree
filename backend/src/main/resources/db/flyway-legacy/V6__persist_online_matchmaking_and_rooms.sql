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
