package com.ludoworldfree.backend.websocket;

import java.util.Arrays;
import java.util.List;
import com.ludoworldfree.backend.chat.ChatJwtHandshakeInterceptor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
@EnableScheduling
public class WebSocketConfig implements WebSocketConfigurer {

    private final GameWebSocketHandler gameWebSocketHandler;
    private final GameRoomWebSocketHandler gameRoomWebSocketHandler;
    private final VoiceCallWebSocketHandler voiceCallWebSocketHandler;
    private final ChatWebSocketHandler chatWebSocketHandler;
    private final ChatJwtHandshakeInterceptor chatJwtHandshakeInterceptor;
    private final List<String> allowedOriginPatterns;

    public WebSocketConfig(
            GameWebSocketHandler gameWebSocketHandler,
            GameRoomWebSocketHandler gameRoomWebSocketHandler,
            VoiceCallWebSocketHandler voiceCallWebSocketHandler,
            ChatWebSocketHandler chatWebSocketHandler,
            ChatJwtHandshakeInterceptor chatJwtHandshakeInterceptor,
            @Value("${app.cors.allowed-origins:*}") String allowedOrigins) {
        this.gameWebSocketHandler = gameWebSocketHandler;
        this.gameRoomWebSocketHandler = gameRoomWebSocketHandler;
        this.voiceCallWebSocketHandler = voiceCallWebSocketHandler;
        this.chatWebSocketHandler = chatWebSocketHandler;
        this.chatJwtHandshakeInterceptor = chatJwtHandshakeInterceptor;
        this.allowedOriginPatterns = Arrays.stream(allowedOrigins.split(","))
                .map(String::trim)
                .filter(origin -> !origin.isEmpty())
                .toList();
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(gameWebSocketHandler, "/ws")
                .setAllowedOriginPatterns(allowedOriginPatterns.toArray(String[]::new));
        registry.addHandler(gameRoomWebSocketHandler, "/ws/game")
                .setAllowedOriginPatterns(allowedOriginPatterns.toArray(String[]::new));
        registry.addHandler(voiceCallWebSocketHandler, "/ws/voice")
                .setAllowedOriginPatterns(allowedOriginPatterns.toArray(String[]::new));
        registry.addHandler(chatWebSocketHandler, "/ws/chat")
                .addInterceptors(chatJwtHandshakeInterceptor)
                .setAllowedOriginPatterns(allowedOriginPatterns.toArray(String[]::new));
    }
}
