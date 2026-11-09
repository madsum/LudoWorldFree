package com.ludoworldfree.backend.websocket;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
@EnableScheduling
public class WebSocketConfig implements WebSocketConfigurer {
    private final GameRoomWebSocketHandler gameRoomWebSocketHandler;

    public WebSocketConfig(GameRoomWebSocketHandler gameRoomWebSocketHandler) {
        this.gameRoomWebSocketHandler = gameRoomWebSocketHandler;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(gameRoomWebSocketHandler, "/ws/game")
                .setAllowedOriginPatterns("*");
    }
}
