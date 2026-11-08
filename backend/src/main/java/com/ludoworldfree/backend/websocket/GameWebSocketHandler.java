package com.ludoworldfree.backend.websocket;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.ludoworldfree.backend.service.MatchmakingService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import java.io.IOException;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator;

@Component
public class GameWebSocketHandler extends TextWebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(GameWebSocketHandler.class);
    private static final int SEND_TIME_LIMIT_MILLIS = 10_000;
    private static final int SEND_BUFFER_SIZE_LIMIT_BYTES = 64 * 1024;
    private static final int MESSAGE_SIZE_LIMIT_BYTES = 64 * 1024;

    private final ObjectMapper objectMapper;
    private final MatchmakingService matchmakingService;
    private final ConcurrentMap<String, WebSocketSession> sessions = new ConcurrentHashMap<>();
    private final ConcurrentMap<String, String> roomBySessionId = new ConcurrentHashMap<>();
    private final ConcurrentMap<String, String> playerBySessionId = new ConcurrentHashMap<>();
    private final ConcurrentMap<String, Set<String>> sessionIdsByRoom = new ConcurrentHashMap<>();

    public GameWebSocketHandler(ObjectMapper objectMapper, MatchmakingService matchmakingService) {
        this.objectMapper = objectMapper;
        this.matchmakingService = matchmakingService;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws IOException {
        sessions.put(session.getId(), new ConcurrentWebSocketSessionDecorator(
                session, SEND_TIME_LIMIT_MILLIS, SEND_BUFFER_SIZE_LIMIT_BYTES));
        ObjectNode connected = objectMapper.createObjectNode()
                .put("type", "connected")
                .put("sessionId", session.getId());
        send(session.getId(), connected);
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws IOException {
        if (message.getPayloadLength() > MESSAGE_SIZE_LIMIT_BYTES) {
            sendError(session.getId(), "message_too_large", "Messages must be 64 KB or smaller.");
            return;
        }

        JsonNode request;
        try {
            request = objectMapper.readTree(message.getPayload());
        } catch (JsonProcessingException exception) {
            sendError(session.getId(), "invalid_json", "Send a valid JSON object.");
            return;
        }

        if (request == null || !request.isObject()) {
            sendError(session.getId(), "invalid_message", "Send a JSON object with a type field.");
            return;
        }

        String type = text(request, "type");
        switch (type) {
            case "ping" -> send(session.getId(), objectMapper.createObjectNode().put("type", "pong"));
            case "join" -> joinRoom(session, request);
            case "leave" -> leaveRoom(session.getId());
            case "event" -> relayEvent(session.getId(), request);
            default -> sendError(session.getId(), "unsupported_type",
                    "Supported message types are ping, join, leave, and event.");
        }
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) {
        log.debug("WebSocket transport error for session {}: {}", session.getId(), exception.getMessage());
        removeSession(session.getId());
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        removeSession(session.getId());
    }

    private void joinRoom(WebSocketSession session, JsonNode request) throws IOException {
        String roomId = text(request, "roomId");
        String playerId = text(request, "playerId");
        if (roomId == null || roomId.isBlank() || playerId == null || playerId.isBlank()) {
            sendError(session.getId(), "invalid_join", "join requires roomId and playerId.");
            return;
        }

        UUID resolvedPlayerId = PlayerIdResolver.resolve(playerId);
        if (!matchmakingService.isPlayerInRoom(resolvedPlayerId, roomId)) {
            sendError(session.getId(), "room_access_denied", "This player is not a participant in that match.");
            return;
        }

        leaveRoom(session.getId());
        sessionIdsByRoom.computeIfAbsent(roomId, ignored -> ConcurrentHashMap.newKeySet()).add(session.getId());
        roomBySessionId.put(session.getId(), roomId);
        playerBySessionId.put(session.getId(), playerId);

        ObjectNode joined = objectMapper.createObjectNode()
                .put("type", "joined")
                .put("roomId", roomId)
                .put("playerId", playerId);
        send(session.getId(), joined);

        ObjectNode playerJoined = objectMapper.createObjectNode()
                .put("type", "player_joined")
                .put("roomId", roomId)
                .put("playerId", playerId);
        broadcast(roomId, playerJoined, session.getId());
    }

    private void relayEvent(String sessionId, JsonNode request) throws IOException {
        String roomId = roomBySessionId.get(sessionId);
        String playerId = playerBySessionId.get(sessionId);
        JsonNode event = request.get("event");
        if (roomId == null || playerId == null) {
            sendError(sessionId, "not_in_room", "Join your matched room before sending game events.");
            return;
        }
        if (event == null || event.isNull()) {
            sendError(sessionId, "missing_event", "event must contain a JSON value.");
            return;
        }

        ObjectNode envelope = objectMapper.createObjectNode()
                .put("type", "event")
                .put("roomId", roomId)
                .put("playerId", playerId);
        envelope.set("event", event);
        broadcast(roomId, envelope, sessionId);
    }

    private void leaveRoom(String sessionId) throws IOException {
        String roomId = roomBySessionId.remove(sessionId);
        String playerId = playerBySessionId.remove(sessionId);
        if (roomId == null) {
            return;
        }

        Set<String> roomSessions = sessionIdsByRoom.get(roomId);
        if (roomSessions != null) {
            roomSessions.remove(sessionId);
            if (roomSessions.isEmpty()) {
                sessionIdsByRoom.remove(roomId, roomSessions);
            }
        }

        ObjectNode left = objectMapper.createObjectNode()
                .put("type", "player_left")
                .put("roomId", roomId)
                .put("playerId", playerId);
        broadcast(roomId, left, sessionId);
    }

    private void broadcast(String roomId, JsonNode message, String excludedSessionId) throws IOException {
        Set<String> roomSessions = sessionIdsByRoom.get(roomId);
        if (roomSessions == null) {
            return;
        }
        TextMessage frame = new TextMessage(objectMapper.writeValueAsString(message));
        for (String sessionId : roomSessions) {
            if (sessionId.equals(excludedSessionId)) {
                continue;
            }
            WebSocketSession recipient = sessions.get(sessionId);
            if (recipient == null || !recipient.isOpen()) {
                removeSession(sessionId);
                continue;
            }
            try {
                recipient.sendMessage(frame);
            } catch (IOException exception) {
                log.debug("Could not send WebSocket message to session {}", sessionId, exception);
                removeSession(sessionId);
            }
        }
    }

    private void sendError(String sessionId, String code, String message) throws IOException {
        ObjectNode error = objectMapper.createObjectNode()
                .put("type", "error")
                .put("code", code)
                .put("message", message);
        send(sessionId, error);
    }

    private void send(String sessionId, JsonNode message) throws IOException {
        WebSocketSession session = sessions.get(sessionId);
        if (session != null && session.isOpen()) {
            session.sendMessage(new TextMessage(objectMapper.writeValueAsString(message)));
        }
    }

    private void removeSession(String sessionId) {
        sessions.remove(sessionId);
        try {
            leaveRoom(sessionId);
        } catch (IOException exception) {
            log.debug("Could not notify room about disconnected session {}", sessionId, exception);
        }
    }

    private String text(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value == null || !value.isTextual() ? null : value.asText();
    }
}
