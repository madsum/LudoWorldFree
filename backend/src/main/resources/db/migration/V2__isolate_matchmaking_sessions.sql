ALTER TABLE matchmaking_tickets
    ADD COLUMN session_id varchar(64);

ALTER TABLE online_match_rooms
    ADD COLUMN player_a_session_id varchar(64),
    ADD COLUMN player_b_session_id varchar(64),
    ADD COLUMN player_c_session_id varchar(64),
    ADD COLUMN player_d_session_id varchar(64);
