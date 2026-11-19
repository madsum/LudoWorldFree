ALTER TABLE online_match_rooms
    ADD COLUMN player_a_last_seen_at timestamptz,
    ADD COLUMN player_b_last_seen_at timestamptz,
    ADD COLUMN player_c_last_seen_at timestamptz,
    ADD COLUMN player_d_last_seen_at timestamptz;
