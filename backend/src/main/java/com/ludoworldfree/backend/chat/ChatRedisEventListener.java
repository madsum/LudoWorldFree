package com.ludoworldfree.backend.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.ludoworldfree.backend.websocket.ChatWebSocketHandler;
import com.ludoworldfree.backend.websocket.VoiceCallWebSocketHandler;
import com.ludoworldfree.backend.realtime.DatabaseRealtimeEventBus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

@Component
public class ChatRedisEventListener {
    private static final Logger log = LoggerFactory.getLogger(ChatRedisEventListener.class);
    private final ChatWebSocketHandler webSocketHandler;
    private final VoiceCallWebSocketHandler voiceCallWebSocketHandler;
    private final com.ludoworldfree.backend.websocket.GameRoomWebSocketHandler gameRoomWebSocketHandler;

    public ChatRedisEventListener(ChatWebSocketHandler webSocketHandler,
                                  VoiceCallWebSocketHandler voiceCallWebSocketHandler,
                                  com.ludoworldfree.backend.websocket.GameRoomWebSocketHandler gameRoomWebSocketHandler,
                                  DatabaseRealtimeEventBus eventBus) {
        this.webSocketHandler = webSocketHandler;
        this.voiceCallWebSocketHandler = voiceCallWebSocketHandler;
        this.gameRoomWebSocketHandler = gameRoomWebSocketHandler;
        eventBus.addListener(this::onEvent);
    }

    public void onEvent(JsonNode event) {
        try {
            JsonNode payload = event.path("payload");
            switch (event.path("route").asText("chat")) {
                case "voice" -> {
                    if (payload.isObject()) voiceCallWebSocketHandler.routeRealtimeEvent(payload);
                }
                case "game_room" -> gameRoomWebSocketHandler.routeRealtimeEvent(event);
                default -> {
                    if (payload.isObject()) webSocketHandler.routeRedisEvent(payload);
                    else webSocketHandler.routeRedisEvent(event);
                }
            }
        } catch (Exception exception) {
            log.warn("Could not route a realtime event: {}", exception.getMessage());
        }
    }
}
