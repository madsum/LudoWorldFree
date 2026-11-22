CREATE TABLE IF NOT EXISTS friend_play_rooms (
    room_id VARCHAR(64) PRIMARY KEY,
    room_code CHAR(8) NOT NULL UNIQUE,
    host_player_id UUID NOT NULL,
    player_count INTEGER NOT NULL CHECK (player_count IN (2, 4)),
    entry_fee BIGINT NOT NULL CHECK (entry_fee >= 0),
    game_mode VARCHAR(16) NOT NULL CHECK (game_mode IN ('CLASSIC', 'FIRST_KILL')),
    voice_chat BOOLEAN NOT NULL DEFAULT FALSE,
    seats_json TEXT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'OPEN',
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_friend_play_rooms_open_expiry
    ON friend_play_rooms (expires_at) WHERE status = 'OPEN';
