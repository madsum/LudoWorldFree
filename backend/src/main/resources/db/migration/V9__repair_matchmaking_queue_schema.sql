-- Keep queue schemas usable when an older deployment was started before the
-- matchmaking migrations were enabled or completed.
ALTER TABLE matchmaking_tickets
    ADD COLUMN IF NOT EXISTS session_id VARCHAR(64),
    ADD COLUMN IF NOT EXISTS game_mode VARCHAR(16) NOT NULL DEFAULT 'CLASSIC',
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE online_match_rooms
    ADD COLUMN IF NOT EXISTS game_mode VARCHAR(16) NOT NULL DEFAULT 'CLASSIC',
    ADD COLUMN IF NOT EXISTS player_a_session_id VARCHAR(64),
    ADD COLUMN IF NOT EXISTS player_b_session_id VARCHAR(64),
    ADD COLUMN IF NOT EXISTS player_c_session_id VARCHAR(64),
    ADD COLUMN IF NOT EXISTS player_d_session_id VARCHAR(64),
    ADD COLUMN IF NOT EXISTS player_a_last_seen_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS player_b_last_seen_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS player_c_last_seen_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS player_d_last_seen_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_matchmaking_tickets_waiting
    ON matchmaking_tickets (game_mode, player_count, entry_fee, last_seen_at, queued_at);
