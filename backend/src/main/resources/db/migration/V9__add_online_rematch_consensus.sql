ALTER TABLE online_match_rooms
    ADD COLUMN IF NOT EXISTS rematch_revision BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS rematch_round_id UUID,
    ADD COLUMN IF NOT EXISTS rematch_requester_id UUID,
    ADD COLUMN IF NOT EXISTS rematch_status VARCHAR(16) NOT NULL DEFAULT 'NONE',
    ADD COLUMN IF NOT EXISTS rematch_accepted_player_ids TEXT NOT NULL DEFAULT '';

UPDATE online_match_rooms
SET rematch_revision = COALESCE(rematch_revision, 0),
    rematch_status = COALESCE(rematch_status, 'NONE'),
    rematch_accepted_player_ids = COALESCE(rematch_accepted_player_ids, '');

ALTER TABLE online_match_rooms
    ALTER COLUMN rematch_revision SET DEFAULT 0,
    ALTER COLUMN rematch_revision SET NOT NULL,
    ALTER COLUMN rematch_status SET DEFAULT 'NONE',
    ALTER COLUMN rematch_status SET NOT NULL,
    ALTER COLUMN rematch_accepted_player_ids SET DEFAULT '',
    ALTER COLUMN rematch_accepted_player_ids SET NOT NULL;
