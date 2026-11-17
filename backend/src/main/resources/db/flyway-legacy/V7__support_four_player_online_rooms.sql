ALTER TABLE matchmaking_tickets
    ADD COLUMN IF NOT EXISTS player_count INTEGER NOT NULL DEFAULT 2;
ALTER TABLE matchmaking_tickets
    ADD COLUMN IF NOT EXISTS selected_color VARCHAR(8) NOT NULL DEFAULT 'red';
CREATE INDEX IF NOT EXISTS idx_matchmaking_tickets_size_fee_queued
    ON matchmaking_tickets (player_count, entry_fee, queued_at);

ALTER TABLE online_match_rooms
    ADD COLUMN IF NOT EXISTS player_count INTEGER NOT NULL DEFAULT 2;
ALTER TABLE online_match_rooms
    ADD COLUMN IF NOT EXISTS player_a_color VARCHAR(8) NOT NULL DEFAULT 'red';
ALTER TABLE online_match_rooms
    ADD COLUMN IF NOT EXISTS player_b_color VARCHAR(8) NOT NULL DEFAULT 'yellow';
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_c_id UUID;
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_c_name VARCHAR(100);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_c_avatar VARCHAR(500);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_c_country VARCHAR(100);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_c_flag VARCHAR(16);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_c_color VARCHAR(8);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_d_id UUID;
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_d_name VARCHAR(100);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_d_avatar VARCHAR(500);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_d_country VARCHAR(100);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_d_flag VARCHAR(16);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_d_color VARCHAR(8);
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_c_connected BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE online_match_rooms ADD COLUMN IF NOT EXISTS player_d_connected BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_online_match_player_c_status
    ON online_match_rooms (player_c_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_online_match_player_d_status
    ON online_match_rooms (player_d_id, status, created_at DESC);
