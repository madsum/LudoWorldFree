ALTER TABLE matchmaking_tickets
    ADD COLUMN IF NOT EXISTS game_mode VARCHAR(16) NOT NULL DEFAULT 'CLASSIC';

ALTER TABLE online_match_rooms
    ADD COLUMN IF NOT EXISTS game_mode VARCHAR(16) NOT NULL DEFAULT 'CLASSIC';

CREATE INDEX IF NOT EXISTS idx_matchmaking_tickets_mode_size_fee_queued
    ON matchmaking_tickets (game_mode, player_count, entry_fee, queued_at);
