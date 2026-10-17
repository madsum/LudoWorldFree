-- Migration V2: Add Daily Rewards Progress and Diamonds to Player Wallets

ALTER TABLE player_wallets ADD COLUMN IF NOT EXISTS diamonds BIGINT NOT NULL DEFAULT 100;

CREATE TABLE IF NOT EXISTS daily_reward_progress (
    id UUID PRIMARY KEY,
    player_id UUID NOT NULL UNIQUE,
    current_streak INT NOT NULL DEFAULT 0,
    last_claim_date DATE,
    last_claim_time TIMESTAMP WITH TIME ZONE,
    bonus_ad_claimed_today BOOLEAN NOT NULL DEFAULT FALSE,
    last_bonus_ad_claim_date DATE,
    version BIGINT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_daily_reward_player_id ON daily_reward_progress(player_id);
