package com.ludoworldfree.backend.chat;

import java.util.List;
import java.util.Map;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.realtime.DatabaseRealtimeEventBus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;

@Component
@ConditionalOnProperty(prefix = "chat.outbox", name = "enabled", havingValue = "true", matchIfMissing = true)
public class ChatOutboxPublisher {
    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final DatabaseRealtimeEventBus realtimeEvents;

    public ChatOutboxPublisher(JdbcTemplate jdbc, ObjectMapper objectMapper,
                               DatabaseRealtimeEventBus realtimeEvents) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
        this.realtimeEvents = realtimeEvents;
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
            try {
                realtimeEvents.publish(Map.of("route", "chat",
                        "payload", objectMapper.readValue(event.json(), Map.class)));
            } catch (Exception exception) {
                throw new IllegalStateException("Chat outbox event could not be published.", exception);
            }
            jdbc.update("""
                    UPDATE chat_outbox
                    SET published_at = CURRENT_TIMESTAMP, attempts = attempts + 1
                    WHERE id = ?
                    """, event.id());
        }
    }

    private record OutboxEvent(long id, String json) {}
}
