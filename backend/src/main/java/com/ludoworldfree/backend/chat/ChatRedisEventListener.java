package com.ludoworldfree.backend.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.websocket.ChatWebSocketHandler;
import com.ludoworldfree.backend.websocket.VoiceCallWebSocketHandler;
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
    private final VoiceCallWebSocketHandler voiceCallWebSocketHandler;

    public ChatRedisEventListener(ObjectMapper objectMapper,
                                  ChatWebSocketHandler webSocketHandler,
                                  VoiceCallWebSocketHandler voiceCallWebSocketHandler) {
        this.objectMapper = objectMapper;
        this.webSocketHandler = webSocketHandler;
        this.voiceCallWebSocketHandler = voiceCallWebSocketHandler;
    }

    @Override
    public void onMessage(Message message, byte[] pattern) {
        try {
            JsonNode event = objectMapper.readTree(
                    new String(message.getBody(), StandardCharsets.UTF_8));
            if ("voice".equals(event.path("route").asText())) {
                JsonNode payload = event.path("payload");
                if (payload.isObject()) voiceCallWebSocketHandler.routeRedisEvent(payload);
            } else {
                webSocketHandler.routeRedisEvent(event);
            }
        } catch (Exception exception) {
            log.warn("Discarding malformed realtime chat event: {}", exception.getMessage());
        }
    }
}
