package com.ludoworldfree.backend.chat;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.realtime.PubSubRealtimeEventBus;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class ChatEventPublisher {
    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final PubSubRealtimeEventBus realtimeEvents;

    public ChatEventPublisher(JdbcTemplate jdbc, ObjectMapper objectMapper,
                              PubSubRealtimeEventBus realtimeEvents) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
        this.realtimeEvents = realtimeEvents;
    }

    public void enqueue(Map<String, Object> event) {
        try {
            jdbc.update("INSERT INTO chat_outbox (event_json) VALUES (?::jsonb)",
                    objectMapper.writeValueAsString(event));
        } catch (JsonProcessingException exception) {
            throw new IllegalArgumentException("Chat event could not be serialized.", exception);
        }
    }

    public void publishEphemeral(Map<String, Object> event) {
        realtimeEvents.publish(Map.of("route", "chat", "payload", event));
    }
}
