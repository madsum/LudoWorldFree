-- Migration V1: Add Game Type Preference and Most-Played Tracking to Player Profiles

ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS preferred_game_type VARCHAR(50) DEFAULT 'CLASSIC';
ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS most_played_game_type VARCHAR(50) DEFAULT 'CLASSIC';
ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS classic_play_count INT DEFAULT 0;
ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS quick_play_count INT DEFAULT 0;
ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS team_up_play_count INT DEFAULT 0;
ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS computer_play_count INT DEFAULT 0;
ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS pass_n_play_play_count INT DEFAULT 0;
