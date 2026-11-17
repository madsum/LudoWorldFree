-- Migration V2: Add Diamonds to Player Wallets

ALTER TABLE player_wallets ADD COLUMN IF NOT EXISTS diamonds BIGINT NOT NULL DEFAULT 100;
