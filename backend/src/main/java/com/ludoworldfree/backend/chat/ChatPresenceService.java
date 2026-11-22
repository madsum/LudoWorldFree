package com.ludoworldfree.backend.chat;

import java.time.Instant;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Shared online leases stored in PostgreSQL so presence works across Cloud Run instances. */
@Service
public class ChatPresenceService {
    private final JdbcTemplate jdbc;
    private final ChatEventPublisher publisher;
    private final long ttlSeconds;
    private final long persistIntervalMillis;
    private final ConcurrentMap<String, Long> persistedHeartbeats = new ConcurrentHashMap<>();

    public ChatPresenceService(JdbcTemplate jdbc, ChatEventPublisher publisher,
                               @Value("${chat.presence.ttl-seconds:90}") long ttlSeconds,
                               @Value("${chat.presence.persist-interval-millis:40000}")
                               long persistIntervalMillis) {
        this.jdbc = jdbc;
        this.publisher = publisher;
        this.ttlSeconds = Math.max(45, ttlSeconds);
        this.persistIntervalMillis = Math.max(20_000, persistIntervalMillis);
    }

    @Transactional
    public void connected(UUID userId, String sessionId) {
        boolean wasOnline = isOnline(userId);
        upsertSession(userId, sessionId);
        updateLastSeen(userId);
        if (!wasOnline) publishPresence(userId, true, null);
    }

    @Transactional
    public void heartbeat(UUID userId, String sessionId) {
        long now = System.currentTimeMillis();
        Long lastPersisted = persistedHeartbeats.get(sessionId);
        if (lastPersisted != null && now - lastPersisted < persistIntervalMillis) return;
        persistedHeartbeats.put(sessionId, now);
        boolean wasOnline = isOnline(userId);
        upsertSession(userId, sessionId);
        updateLastSeen(userId);
        if (!wasOnline) publishPresence(userId, true, null);
    }

    @Transactional
    public void disconnected(UUID userId, String sessionId) {
        persistedHeartbeats.remove(sessionId);
        jdbc.update("DELETE FROM realtime_presence_sessions WHERE session_id = ?", sessionId);
        if (isOnline(userId)) return;
        Instant lastSeen = Instant.now();
        updateLastSeen(userId, lastSeen);
        publishPresence(userId, false, lastSeen);
    }

    @Transactional(readOnly = true)
    public boolean isOnline(UUID userId) {
        Boolean online = jdbc.queryForObject("""
                SELECT EXISTS (
                    SELECT 1 FROM realtime_presence_sessions
                    WHERE user_id = ?
                      AND last_heartbeat_at > CURRENT_TIMESTAMP - (? * INTERVAL '1 second')
                )
                """, Boolean.class, userId, ttlSeconds);
        return Boolean.TRUE.equals(online);
    }

    @Transactional(readOnly = true)
    public Map<UUID, Boolean> onlineStatuses(Collection<UUID> userIds) {
        Set<UUID> uniqueIds = new LinkedHashSet<>(userIds);
        if (uniqueIds.isEmpty()) return Map.of();
        Map<UUID, Boolean> result = new LinkedHashMap<>();
        uniqueIds.forEach(userId -> result.put(userId, false));
        String placeholders = String.join(",", java.util.Collections.nCopies(uniqueIds.size(), "?"));
        Object[] arguments = new Object[uniqueIds.size() + 1];
        int index = 0;
        for (UUID userId : uniqueIds) arguments[index++] = userId;
        arguments[index] = ttlSeconds;
        List<UUID> onlineIds = jdbc.query("""
                SELECT DISTINCT user_id FROM realtime_presence_sessions
                WHERE user_id IN (%s)
                  AND last_heartbeat_at > CURRENT_TIMESTAMP - (? * INTERVAL '1 second')
                """.formatted(placeholders), (rs, rowNum) -> rs.getObject(1, UUID.class), arguments);
        onlineIds.forEach(userId -> result.put(userId, true));
        return result;
    }

    @Transactional(readOnly = true)
    public Instant lastSeen(UUID userId) {
        List<Instant> values = jdbc.query("""
                SELECT last_seen_at FROM chat_presence WHERE user_id = ?
                """, (rs, rowNum) -> rs.getTimestamp(1).toInstant(), userId);
        return values.isEmpty() ? null : values.getFirst();
    }

    @Scheduled(fixedDelayString = "${chat.presence.cleanup-millis:30000}")
    @Transactional
    public void removeExpiredSessions() {
        List<UUID> expiredUsers = jdbc.query("""
                DELETE FROM realtime_presence_sessions
                WHERE last_heartbeat_at <= CURRENT_TIMESTAMP - (? * INTERVAL '1 second')
                RETURNING user_id
                """, (rs, rowNum) -> rs.getObject(1, UUID.class), ttlSeconds);
        for (UUID userId : new LinkedHashSet<>(expiredUsers)) {
            if (isOnline(userId)) continue;
            Instant lastSeen = Instant.now();
            updateLastSeen(userId, lastSeen);
            publishPresence(userId, false, lastSeen);
        }
    }

    private void upsertSession(UUID userId, String sessionId) {
        jdbc.update("""
                INSERT INTO realtime_presence_sessions (session_id, user_id, last_heartbeat_at)
                VALUES (?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT (session_id) DO UPDATE SET
                    user_id = EXCLUDED.user_id,
                    last_heartbeat_at = CURRENT_TIMESTAMP
                """, sessionId, userId);
    }

    private void updateLastSeen(UUID userId) {
        updateLastSeen(userId, Instant.now());
    }

    private void updateLastSeen(UUID userId, Instant lastSeen) {
        jdbc.update("""
                INSERT INTO chat_presence (user_id, last_seen_at)
                VALUES (?, ?)
                ON CONFLICT (user_id) DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at
                """, userId, lastSeen);
    }

    private void publishPresence(UUID userId, boolean online, Instant lastSeen) {
        List<String> recipients = jdbc.query("""
                SELECT CASE WHEN requester_id = ? THEN addressee_id ELSE requester_id END
                FROM friendships
                WHERE status = 'ACCEPTED' AND (requester_id = ? OR addressee_id = ?)
                """, (rs, rowNum) -> rs.getObject(1, UUID.class).toString(),
                userId, userId, userId);
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("type", "presence");
        event.put("recipients", recipients);
        event.put("userId", userId.toString());
        event.put("online", online);
        event.put("lastSeenAt", lastSeen == null ? null : lastSeen.toString());
        publisher.publishEphemeral(event);
    }
}
