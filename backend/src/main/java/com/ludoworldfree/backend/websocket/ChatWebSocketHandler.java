package com.ludoworldfree.backend.websocket;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.chat.ChatConversationService;
import com.ludoworldfree.backend.chat.ChatEventPublisher;
import com.ludoworldfree.backend.chat.ChatJwtHandshakeInterceptor;
import com.ludoworldfree.backend.chat.ChatMessage;
import com.ludoworldfree.backend.chat.ChatMessageService;
import com.ludoworldfree.backend.chat.ChatPresenceService;
import java.io.IOException;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator;
import org.springframework.web.socket.handler.TextWebSocketHandler;

@Component
public class ChatWebSocketHandler extends TextWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(ChatWebSocketHandler.class);
    private static final int MESSAGE_LIMIT_BYTES = 64 * 1024;
    private static final TypeReference<List<Map<String, Object>>> ATTACHMENTS_TYPE =
            new TypeReference<>() {};

    private final ObjectMapper objectMapper;
    private final ChatMessageService messageService;
    private final ChatConversationService conversationService;
    private final ChatPresenceService presenceService;
    private final ChatEventPublisher eventPublisher;
    private final ConcurrentMap<String, Connection> connections = new ConcurrentHashMap<>();
    private final ConcurrentMap<UUID, Set<String>> sessionsByUser = new ConcurrentHashMap<>();

    public ChatWebSocketHandler(ObjectMapper objectMapper,
                                ChatMessageService messageService,
                                ChatConversationService conversationService,
                                ChatPresenceService presenceService,
                                ChatEventPublisher eventPublisher) {
        this.objectMapper = objectMapper;
        this.messageService = messageService;
        this.conversationService = conversationService;
        this.presenceService = presenceService;
        this.eventPublisher = eventPublisher;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws IOException {
        Object userValue = session.getAttributes().get(ChatJwtHandshakeInterceptor.USER_ID_ATTRIBUTE);
        if (!(userValue instanceof UUID userId)) {
            session.close(CloseStatus.NOT_ACCEPTABLE.withReason("A valid JWT is required."));
            return;
        }
        WebSocketSession decorated = new ConcurrentWebSocketSessionDecorator(session, 10_000, 256 * 1024);
        Connection connection = new Connection(userId, decorated);
        connections.put(session.getId(), connection);
        sessionsByUser.computeIfAbsent(userId, ignored -> ConcurrentHashMap.newKeySet())
                .add(session.getId());
        presenceService.connected(userId, "chat:" + session.getId());
        send(session.getId(), Map.of("type", "connected", "userId", userId.toString(),
                "serverTime", Instant.now().toString()));
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) {
        if (message.getPayloadLength() > MESSAGE_LIMIT_BYTES) {
            sendError(session.getId(), "message_too_large", "Messages must be 64 KB or smaller.");
            return;
        }
        Connection connection = connections.get(session.getId());
        if (connection == null) {
            sendError(session.getId(), "unauthorized", "Reconnect using a valid access token.");
            return;
        }
        try {
            JsonNode request = objectMapper.readTree(message.getPayload());
            if (request == null || !request.isObject()) {
                sendError(session.getId(), "invalid_message", "Send a JSON object with a type field.");
                return;
            }
            switch (request.path("type").asText()) {
                case "heartbeat" -> heartbeat(session, connection);
                case "subscribe" -> subscribe(session, connection, request);
                case "send" -> sendMessage(session, connection, request);
                case "delivered" -> receipt(session, connection, request, false);
                case "read" -> receipt(session, connection, request, true);
                case "typing" -> typing(session, connection, request);
                default -> sendError(session.getId(), "unsupported_type",
                        "Supported events: heartbeat, subscribe, send, delivered, read, typing.");
            }
        } catch (ResponseStatusException exception) {
            sendError(session.getId(), errorCode(exception.getStatusCode()), exception.getReason());
        } catch (IllegalArgumentException exception) {
            sendError(session.getId(), "invalid_message", "The message contains invalid fields.");
        } catch (Exception exception) {
            log.debug("Chat message failed for session {}: {}", session.getId(), exception.getMessage());
            sendError(session.getId(), "server_error", "The chat message could not be processed.");
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        removeConnection(session.getId());
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) {
        log.debug("Chat socket error for {}: {}", session.getId(), exception.getMessage());
        removeConnection(session.getId());
    }

    public void routeRealtimeEvent(JsonNode event) {
        JsonNode recipients = event.path("recipients");
        if (!recipients.isArray()) return;
        String type = event.path("type").asText();
        if ("typing".equals(type) && event.path("expiresAt").asLong(0) < Instant.now().toEpochMilli()) {
            return;
        }
        String json = event.toString();
        for (JsonNode recipient : recipients) {
            UUID userId;
            try {
                userId = UUID.fromString(recipient.asText());
            } catch (IllegalArgumentException exception) {
                continue;
            }
            Set<String> sessionIds = sessionsByUser.get(userId);
            if (sessionIds == null) continue;
            for (String sessionId : sessionIds) sendRaw(sessionId, json);
        }
    }

    private void heartbeat(WebSocketSession session, Connection connection) {
        presenceService.heartbeat(connection.userId, "chat:" + session.getId());
        send(session.getId(), Map.of("type", "heartbeat_ack", "serverTime", Instant.now().toString()));
    }

    private void subscribe(WebSocketSession session, Connection connection, JsonNode request) {
        JsonNode ids = request.path("conversationIds");
        if (!ids.isArray() || ids.size() > 200) {
            sendError(session.getId(), "invalid_subscribe", "conversationIds must be an array of at most 200 IDs.");
            return;
        }
        for (JsonNode idNode : ids) {
            UUID conversationId = UUID.fromString(idNode.asText());
            conversationService.requireParticipant(conversationId, connection.userId);
            connection.subscribedConversations.add(conversationId);
        }
        send(session.getId(), Map.of("type", "subscribed", "count", ids.size()));
    }

    private void sendMessage(WebSocketSession session, Connection connection, JsonNode request) {
        UUID conversationId = UUID.fromString(request.path("conversationId").asText());
        UUID clientMessageId = UUID.fromString(request.path("clientMessageId").asText());
        List<Map<String, Object>> attachments = objectMapper.convertValue(
                request.path("attachments").isArray() ? request.path("attachments") : objectMapper.createArrayNode(),
                ATTACHMENTS_TYPE);
        Long replyToSequence = request.path("replyToSequence").canConvertToLong()
                ? request.path("replyToSequence").asLong() : null;
        ChatMessage saved = messageService.send(connection.userId, conversationId,
                new ChatMessageService.SendRequest(
                        clientMessageId,
                        request.path("body").isNull() ? null : request.path("body").asText(),
                        request.path("ciphertext").isNull() ? null : request.path("ciphertext").asText(),
                        request.path("encrypted").asBoolean(false),
                        request.path("contentType").asText("TEXT"),
                        attachments, replyToSequence));
        // The transactional service has returned only after the message and its
        // outbox event committed, so this ACK means SENT, not merely received.
        send(session.getId(), Map.of("type", "sent", "message", saved.toMap()));
    }

    private void receipt(WebSocketSession session, Connection connection,
                         JsonNode request, boolean read) {
        UUID conversationId = UUID.fromString(request.path("conversationId").asText());
        long sequence = request.path("sequence").asLong(-1);
        if (sequence <= 0) throw new IllegalArgumentException("sequence is required");
        if (read) messageService.markRead(connection.userId, conversationId, sequence);
        else messageService.markDelivered(connection.userId, conversationId, sequence);
        send(session.getId(), Map.of("type", "receipt_ack", "status", read ? "READ" : "DELIVERED",
                "conversationId", conversationId.toString(), "sequence", sequence));
    }

    private void typing(WebSocketSession session, Connection connection, JsonNode request) {
        UUID conversationId = UUID.fromString(request.path("conversationId").asText());
        conversationService.requireParticipant(conversationId, connection.userId);
        boolean isTyping = request.path("isTyping").asBoolean(false);
        List<String> recipients = conversationService.participantIds(conversationId).stream()
                .filter(id -> !id.equals(connection.userId)).map(UUID::toString).toList();
        Map<String, Object> event = Map.of(
                "type", "typing",
                "recipients", recipients,
                "conversationId", conversationId.toString(),
                "userId", connection.userId.toString(),
                "isTyping", isTyping,
                "expiresAt", Instant.now().plusSeconds(5).toEpochMilli());
        // Typing is deliberately ephemeral and never written to PostgreSQL.
        presenceService.heartbeat(connection.userId, "chat:" + session.getId());
        eventPublisher.publishEphemeral(event);
    }

    private void removeConnection(String sessionId) {
        Connection connection = connections.remove(sessionId);
        if (connection == null) return;
        Set<String> sessions = sessionsByUser.get(connection.userId);
        if (sessions != null) {
            sessions.remove(sessionId);
            if (sessions.isEmpty()) sessionsByUser.remove(connection.userId, sessions);
        }
        try {
            presenceService.disconnected(connection.userId, "chat:" + sessionId);
        } catch (Exception exception) {
            log.warn("Could not update chat presence for {}: {}",
                    connection.userId, exception.getMessage());
        }
    }

    private void send(String sessionId, Object value) {
        try {
            sendRaw(sessionId, objectMapper.writeValueAsString(value));
        } catch (Exception exception) {
            removeConnection(sessionId);
        }
    }

    private void sendRaw(String sessionId, String json) {
        Connection connection = connections.get(sessionId);
        if (connection == null || !connection.session.isOpen()) return;
        try {
            connection.session.sendMessage(new TextMessage(json));
        } catch (IOException exception) {
            removeConnection(sessionId);
        }
    }

    private void sendError(String sessionId, String code, String message) {
        send(sessionId, Map.of("type", "error", "code", code,
                "message", message == null ? "The request was invalid." : message));
    }

    private String errorCode(HttpStatusCode status) {
        return "http_" + status.value();
    }

    private static final class Connection {
        private final UUID userId;
        private final WebSocketSession session;
        private final Set<UUID> subscribedConversations = ConcurrentHashMap.newKeySet();

        private Connection(UUID userId, WebSocketSession session) {
            this.userId = userId;
            this.session = session;
        }
    }

}
