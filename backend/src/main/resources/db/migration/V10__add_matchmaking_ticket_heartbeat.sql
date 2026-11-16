ALTER TABLE matchmaking_tickets
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMP WITH TIME ZONE;

UPDATE matchmaking_tickets
SET last_seen_at = queued_at
WHERE last_seen_at IS NULL;

ALTER TABLE matchmaking_tickets
    ALTER COLUMN last_seen_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_matchmaking_tickets_last_seen
    ON matchmaking_tickets (last_seen_at);
