package com.ludoworldfree.backend.chat;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

@Service
public class ChatPresenceService {
    private final StringRedisTemplate redis;
    private final JdbcTemplate jdbc;
    private final ChatEventPublisher publisher;
    private final String instanceId = UUID.randomUUID().toString();
    private final long ttlSeconds;

    public ChatPresenceService(StringRedisTemplate redis, JdbcTemplate jdbc,
                               ChatEventPublisher publisher,
                               @Value("${chat.presence.ttl-seconds:65}") long ttlSeconds) {
        this.redis = redis;
        this.jdbc = jdbc;
        this.publisher = publisher;
        this.ttlSeconds = Math.max(30, ttlSeconds);
    }

    public void heartbeat(UUID userId, String sessionId) {
        long now = System.currentTimeMillis();
        String key = key(userId);
        String member = instanceId + ":" + sessionId;
        redis.opsForZSet().removeRangeByScore(key, 0, now);
        Long previousCount = redis.opsForZSet().zCard(key);
        redis.opsForZSet().add(key, member, now + TimeUnit.SECONDS.toMillis(ttlSeconds));
        redis.expire(key, ttlSeconds, TimeUnit.SECONDS);
        Instant lastSeen = Instant.now();
        jdbc.update("""
                INSERT INTO chat_presence (user_id, last_seen_at)
                VALUES (?, ?)
                ON CONFLICT (user_id) DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at
                """, userId, lastSeen);
        if (previousCount == null || previousCount == 0) {
            publishPresence(userId, true, null);
        }
    }

    public void disconnected(UUID userId, String sessionId) {
        String key = key(userId);
        long now = System.currentTimeMillis();
        redis.opsForZSet().remove(key, instanceId + ":" + sessionId);
        redis.opsForZSet().removeRangeByScore(key, 0, now);
        Long count = redis.opsForZSet().zCard(key);
        if (count != null && count > 0) return;
        redis.delete(key);
        Instant lastSeen = Instant.now();
        jdbc.update("""
                INSERT INTO chat_presence (user_id, last_seen_at)
                VALUES (?, ?)
                ON CONFLICT (user_id) DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at
                """, userId, lastSeen);
        publishPresence(userId, false, lastSeen);
    }

    public boolean isOnline(UUID userId) {
        String key = key(userId);
        long now = System.currentTimeMillis();
        redis.opsForZSet().removeRangeByScore(key, 0, now);
        Long count = redis.opsForZSet().zCard(key);
        return count != null && count > 0;
    }

    public Instant lastSeen(UUID userId) {
        List<Instant> values = jdbc.query("""
                SELECT last_seen_at FROM chat_presence WHERE user_id = ?
                """, (rs, rowNum) -> rs.getTimestamp(1).toInstant(), userId);
        return values.isEmpty() ? null : values.getFirst();
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

    private String key(UUID userId) {
        return "ludoworld:chat:presence:" + userId;
    }
}
