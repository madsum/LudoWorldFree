package com.ludoworldfree.backend.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.ludoworldfree.backend.websocket.ChatWebSocketHandler;
import com.ludoworldfree.backend.websocket.VoiceCallWebSocketHandler;
import com.ludoworldfree.backend.realtime.PubSubRealtimeEventBus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

@Component
public class RealtimeEventRouter {
    private static final Logger log = LoggerFactory.getLogger(RealtimeEventRouter.class);
    private final ChatWebSocketHandler webSocketHandler;
    private final VoiceCallWebSocketHandler voiceCallWebSocketHandler;
    private final com.ludoworldfree.backend.websocket.GameRoomWebSocketHandler gameRoomWebSocketHandler;

    public RealtimeEventRouter(ChatWebSocketHandler webSocketHandler,
                                  VoiceCallWebSocketHandler voiceCallWebSocketHandler,
                                  com.ludoworldfree.backend.websocket.GameRoomWebSocketHandler gameRoomWebSocketHandler,
                                  PubSubRealtimeEventBus eventBus) {
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
                    if (payload.isObject()) webSocketHandler.routeRealtimeEvent(payload);
                    else webSocketHandler.routeRealtimeEvent(event);
                }
            }
        } catch (Exception exception) {
            log.warn("Could not route a realtime event: {}", exception.getMessage());
        }
    }
}
