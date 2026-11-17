CREATE TABLE IF NOT EXISTS daily_goals (
    id UUID PRIMARY KEY,
    player_id UUID NOT NULL,
    goal_date DATE NOT NULL,
    goal_type VARCHAR(40) NOT NULL,
    progress INTEGER NOT NULL DEFAULT 0,
    target INTEGER NOT NULL,
    reward_amount BIGINT NOT NULL,
    claimed BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT uk_daily_goal_player_date_type UNIQUE (player_id, goal_date, goal_type)
);

CREATE TABLE IF NOT EXISTS daily_goal_events (
    id UUID PRIMARY KEY,
    player_id UUID NOT NULL,
    event_id VARCHAR(160) NOT NULL,
    event_type VARCHAR(40) NOT NULL,
    game_id VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_daily_goal_event_player_event UNIQUE (player_id, event_id)
);

CREATE INDEX IF NOT EXISTS idx_daily_goals_player_date ON daily_goals (player_id, goal_date);
