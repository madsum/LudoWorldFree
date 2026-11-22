package com.ludoworldfree.backend.chat;

import java.util.List;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class ChatOutboxPublisher {
    private final JdbcTemplate jdbc;
    private final StringRedisTemplate redis;

    public ChatOutboxPublisher(JdbcTemplate jdbc, StringRedisTemplate redis) {
        this.jdbc = jdbc;
        this.redis = redis;
    }

    @Scheduled(fixedDelayString = "${chat.outbox.poll-millis:100}")
    @Transactional
    public void publishBatch() {
        List<OutboxEvent> events = jdbc.query("""
                SELECT id, event_json::text AS event_json
                FROM chat_outbox
                WHERE published_at IS NULL
                ORDER BY id
                FOR UPDATE SKIP LOCKED
                LIMIT 100
                """, (rs, rowNum) -> new OutboxEvent(
                rs.getLong("id"), rs.getString("event_json")));
        for (OutboxEvent event : events) {
            redis.convertAndSend(ChatEventPublisher.CHANNEL, event.json());
            jdbc.update("""
                    UPDATE chat_outbox
                    SET published_at = CURRENT_TIMESTAMP, attempts = attempts + 1
                    WHERE id = ?
                    """, event.id());
        }
    }

    private record OutboxEvent(long id, String json) {}
}
