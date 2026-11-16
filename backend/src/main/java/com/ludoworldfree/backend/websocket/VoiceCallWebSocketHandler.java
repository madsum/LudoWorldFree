package com.ludoworldfree.backend.websocket;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.model.Friendship;
import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.repository.FriendshipRepository;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import org.springframework.web.util.UriComponentsBuilder;

import java.io.IOException;
import java.net.URI;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class VoiceCallWebSocketHandler extends TextWebSocketHandler {
    private static final int MAX_MESSAGE_CHARS = 32_000;
    private static final String PLAYER_ATTRIBUTE = "voicePlayerId";

    private final ObjectMapper objectMapper;
    private final FriendshipRepository friendshipRepository;
    private final PlayerProfileRepository profileRepository;
    private final Map<UUID, WebSocketSession> sessions = new ConcurrentHashMap<>();

    public VoiceCallWebSocketHandler(ObjectMapper objectMapper,
                                     FriendshipRepository friendshipRepository,
                                     PlayerProfileRepository profileRepository) {
        this.objectMapper = objectMapper;
        this.friendshipRepository = friendshipRepository;
        this.profileRepository = profileRepository;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws IOException {
        URI uri = session.getUri();
        String rawPlayerId = uri == null ? null : UriComponentsBuilder.fromUri(uri)
                .build().getQueryParams().getFirst("playerId");
        UUID playerId = parsePlayerId(rawPlayerId);
        if (playerId == null || !profileRepository.existsByUserId(playerId)) {
            sendError(session, "VOICE_CONNECTION_REJECTED", "Sign in to use voice calls.");
            session.close(CloseStatus.POLICY_VIOLATION);
            return;
        }
        session.getAttributes().put(PLAYER_ATTRIBUTE, playerId);
        WebSocketSession decorated = new ConcurrentWebSocketSessionDecorator(
                session, 10_000, 64_000);
        WebSocketSession previous = sessions.put(playerId, decorated);
        if (previous != null && previous.isOpen()) previous.close(CloseStatus.NORMAL);
        send(decorated, Map.of("type", "voice_ready", "playerId", playerId.toString()));
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message)
            throws IOException {
        UUID senderId = (UUID) session.getAttributes().get(PLAYER_ATTRIBUTE);
        if (senderId == null) return;
        if (message.getPayloadLength() > MAX_MESSAGE_CHARS) {
            sendError(session, "VOICE_MESSAGE_TOO_LARGE", "Voice-call message is too large.");
            return;
        }
        JsonNode payload;
        try {
            payload = objectMapper.readTree(message.getPayload());
        } catch (Exception exception) {
            sendError(session, "VOICE_INVALID_MESSAGE", "Voice-call message is invalid.");
            return;
        }
        String type = payload.path("type").asText("");
        UUID targetId = parsePlayerId(payload.path("targetPlayerId").asText(null));
        String callId = payload.path("callId").asText("");
        if (!isCurrentSession(session, senderId) || targetId == null
                || senderId.equals(targetId) || callId.isBlank()
                || !areAcceptedBuddies(senderId, targetId)) {
            sendError(session, "VOICE_CALL_BUDDY_REQUIRED",
                    "Voice calls are available between accepted buddies only.");
            return;
        }

        WebSocketSession recipient = sessions.get(targetId);
        if (recipient == null || !recipient.isOpen()) {
            if ("voice_call_request".equals(type)) {
                sendError(session, "VOICE_CALL_PLAYER_UNAVAILABLE",
                        "Your buddy is offline and cannot take a call right now.");
            }
            return;
        }

        if ("voice_call_request".equals(type)) {
            PlayerProfile caller = profileRepository.findByUserId(senderId).orElse(null);
            send(recipient, Map.of(
                    "type", "voice_call_incoming",
                    "fromPlayerId", senderId.toString(),
                    "fromPlayerName", caller == null ? "Buddy" : caller.getDisplayName(),
                    "callId", callId));
            return;
        }

        if (!switch (type) {
            case "voice_call_accept", "voice_call_decline", "voice_call_offer",
                    "voice_call_answer", "voice_call_ice", "voice_call_end" -> true;
            default -> false;
        }) {
            sendError(session, "VOICE_UNKNOWN_MESSAGE", "Unsupported voice-call message.");
            return;
        }

        Map<String, Object> relayed = new java.util.LinkedHashMap<>();
        relayed.put("type", type);
        relayed.put("fromPlayerId", senderId.toString());
        relayed.put("callId", callId);
        if (payload.has("description")) {
            relayed.put("description", objectMapper.convertValue(
                    payload.get("description"), Map.class));
        }
        if (payload.has("candidate")) {
            relayed.put("candidate", objectMapper.convertValue(
                    payload.get("candidate"), Map.class));
        }
        send(recipient, relayed);
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        UUID playerId = (UUID) session.getAttributes().get(PLAYER_ATTRIBUTE);
        if (playerId != null) sessions.computeIfPresent(playerId,
                (ignored, active) -> active.getId().equals(session.getId()) ? null : active);
    }

    private boolean isCurrentSession(WebSocketSession session, UUID playerId) {
        WebSocketSession active = sessions.get(playerId);
        return active != null && active.getId().equals(session.getId());
    }

    private boolean areAcceptedBuddies(UUID firstPlayerId, UUID secondPlayerId) {
        return friendshipRepository
                .findByRequesterIdAndAddresseeId(firstPlayerId, secondPlayerId)
                .or(() -> friendshipRepository
                        .findByRequesterIdAndAddresseeId(secondPlayerId, firstPlayerId))
                .map(friendship -> friendship.getStatus() == Friendship.Status.ACCEPTED)
                .orElse(false);
    }

    private void send(WebSocketSession session, Map<String, Object> payload) {
        if (session == null || !session.isOpen()) return;
        try {
            synchronized (session) {
                session.sendMessage(new TextMessage(objectMapper.writeValueAsString(payload)));
            }
        } catch (IOException exception) {
            try {
                session.close(CloseStatus.SERVER_ERROR);
            } catch (IOException ignored) {}
        }
    }

    private void sendError(WebSocketSession session, String code, String message) {
        send(session, Map.of("type", "error", "code", code, "message", message));
    }

    private static UUID parsePlayerId(String value) {
        try {
            return value == null ? null : UUID.fromString(value);
        } catch (IllegalArgumentException exception) {
            return null;
        }
    }
}
