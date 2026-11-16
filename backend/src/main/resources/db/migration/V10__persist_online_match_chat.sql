CREATE TABLE IF NOT EXISTS online_match_chat_events (
    id BIGSERIAL PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL,
    player_id UUID NOT NULL,
    message_text VARCHAR(200) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_online_match_chat_room_id
    ON online_match_chat_events (room_id, id);
