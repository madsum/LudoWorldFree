CREATE TABLE IF NOT EXISTS realtime_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_realtime_events_created_at
    ON realtime_events (created_at);

CREATE TABLE IF NOT EXISTS realtime_presence_sessions (
    session_id VARCHAR(160) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    last_heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_realtime_presence_user_heartbeat
    ON realtime_presence_sessions (user_id, last_heartbeat_at DESC);
