ALTER TABLE buddy_game_invites
    ADD COLUMN IF NOT EXISTS decline_reason VARCHAR(500);
