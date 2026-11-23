-- Presence records are transient transport state and can include legacy player
-- profiles that predate user_accounts. Do not let account foreign keys reject
-- voice WebSocket handshakes or last-seen updates for those players.
ALTER TABLE realtime_presence_sessions
    DROP CONSTRAINT IF EXISTS realtime_presence_sessions_user_id_fkey;

ALTER TABLE chat_presence
    DROP CONSTRAINT IF EXISTS chat_presence_user_id_fkey;
