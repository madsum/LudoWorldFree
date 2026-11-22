package com.ludoworldfree.backend.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.websocket.ChatWebSocketHandler;
import java.nio.charset.StandardCharsets;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.connection.Message;
import org.springframework.data.redis.connection.MessageListener;
import org.springframework.stereotype.Component;

@Component
public class ChatRedisEventListener implements MessageListener {
    private static final Logger log = LoggerFactory.getLogger(ChatRedisEventListener.class);
    private final ObjectMapper objectMapper;
    private final ChatWebSocketHandler webSocketHandler;

    public ChatRedisEventListener(ObjectMapper objectMapper,
                                  ChatWebSocketHandler webSocketHandler) {
        this.objectMapper = objectMapper;
        this.webSocketHandler = webSocketHandler;
    }

    @Override
    public void onMessage(Message message, byte[] pattern) {
        try {
            JsonNode event = objectMapper.readTree(
                    new String(message.getBody(), StandardCharsets.UTF_8));
            webSocketHandler.routeRedisEvent(event);
        } catch (Exception exception) {
            log.warn("Discarding malformed realtime chat event: {}", exception.getMessage());
        }
    }
}
