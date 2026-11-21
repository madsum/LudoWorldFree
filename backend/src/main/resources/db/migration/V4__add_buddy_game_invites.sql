CREATE TABLE IF NOT EXISTS buddy_game_invites (
    id UUID PRIMARY KEY,
    requester_id UUID NOT NULL,
    target_id UUID NOT NULL,
    entry_fee BIGINT NOT NULL,
    requester_session_id VARCHAR(64) NOT NULL,
    requester_color VARCHAR(8) NOT NULL,
    target_session_id VARCHAR(64),
    target_color VARCHAR(8),
    room_id VARCHAR(64),
    status VARCHAR(16) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_buddy_game_invites_target_status_expiry
    ON buddy_game_invites (target_id, status, expires_at);

CREATE INDEX IF NOT EXISTS idx_buddy_game_invites_requester_created
    ON buddy_game_invites (requester_id, created_at DESC);
