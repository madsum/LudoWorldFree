ALTER TABLE player_wallets ADD COLUMN IF NOT EXISTS daily_bonus_claim_date DATE;
ALTER TABLE player_wallets ADD COLUMN IF NOT EXISTS daily_bonus_streak INTEGER NOT NULL DEFAULT 0;
