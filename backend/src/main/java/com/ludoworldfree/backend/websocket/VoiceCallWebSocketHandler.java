package com.ludoworldfree.backend.websocket;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.model.Friendship;
import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.repository.FriendshipRepository;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import com.ludoworldfree.backend.chat.ChatEventPublisher;
import com.ludoworldfree.backend.chat.ChatPresenceService;
import com.ludoworldfree.backend.realtime.DatabaseRealtimeEventBus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import org.springframework.web.util.UriComponentsBuilder;

import java.io.IOException;
import java.net.URI;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class VoiceCallWebSocketHandler extends TextWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(VoiceCallWebSocketHandler.class);
    private static final int MAX_MESSAGE_CHARS = 32_000;
    private static final String PLAYER_ATTRIBUTE = "voicePlayerId";
    private final ObjectMapper objectMapper;
    private final FriendshipRepository friendshipRepository;
    private final PlayerProfileRepository profileRepository;
    private final DatabaseRealtimeEventBus realtimeEvents;
    private final ChatPresenceService presenceService;
    private final Map<UUID, WebSocketSession> sessions = new ConcurrentHashMap<>();

    public VoiceCallWebSocketHandler(ObjectMapper objectMapper,
                                     FriendshipRepository friendshipRepository,
                                     PlayerProfileRepository profileRepository,
                                     DatabaseRealtimeEventBus realtimeEvents,
                                     ChatPresenceService presenceService) {
        this.objectMapper = objectMapper;
        this.friendshipRepository = friendshipRepository;
        this.profileRepository = profileRepository;
        this.realtimeEvents = realtimeEvents;
        this.presenceService = presenceService;
    }

    public boolean isOnline(UUID playerId) {
        WebSocketSession localSession = sessions.get(playerId);
        if (localSession != null && localSession.isOpen()) return true;
        return onlineStatuses(List.of(playerId)).getOrDefault(playerId, false);
    }

    public Map<UUID, Boolean> onlineStatuses(Collection<UUID> playerIds) {
        Set<UUID> uniqueIds = new LinkedHashSet<>(playerIds);
        if (uniqueIds.isEmpty()) return Map.of();
        Map<UUID, Boolean> statuses = new LinkedHashMap<>(
                presenceService.onlineStatuses(uniqueIds));
        for (UUID playerId : uniqueIds) {
            WebSocketSession session = sessions.get(playerId);
            if (session != null && session.isOpen()) statuses.put(playerId, true);
        }
        return statuses;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws IOException {
        URI uri = session.getUri();
        String rawPlayerId = uri == null ? null : UriComponentsBuilder.fromUri(uri)
                .build().getQueryParams().getFirst("playerId");
        UUID playerId = rawPlayerId == null || rawPlayerId.isBlank()
                ? null : PlayerIdResolver.resolve(rawPlayerId);
        if (playerId == null || !profileRepository.existsByUserId(playerId)) {
            sendError(session, "VOICE_CONNECTION_REJECTED",
                    "Voice calling is unavailable for this profile.");
            session.close(CloseStatus.POLICY_VIOLATION);
            return;
        }
        session.getAttributes().put(PLAYER_ATTRIBUTE, playerId);
        WebSocketSession decorated = new ConcurrentWebSocketSessionDecorator(
                session, 10_000, 64_000);
        WebSocketSession previous = sessions.put(playerId, decorated);
        presenceService.connected(playerId, "voice:" + session.getId());
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
        if ("voice_heartbeat".equals(type)) {
            if (isCurrentSession(session, senderId)) {
                presenceService.heartbeat(senderId, "voice:" + session.getId());
                send(session, Map.of("type", "voice_heartbeat_ack"));
            }
            return;
        }
        UUID targetId = parsePlayerId(payload.path("targetPlayerId").asText(null));
        String callId = payload.path("callId").asText("");
        if (!isCurrentSession(session, senderId) || targetId == null
                || senderId.equals(targetId) || callId.isBlank()
                || !areAcceptedBuddies(senderId, targetId)) {
            sendError(session, "VOICE_CALL_BUDDY_REQUIRED",
                    "Voice calls are available between accepted buddies only.");
            return;
        }

        if ("voice_call_request".equals(type)) {
            if (!isOnline(targetId)) {
                sendError(session, "VOICE_CALL_PLAYER_UNAVAILABLE",
                        "Your buddy is offline and cannot take a call right now.");
                return;
            }
            PlayerProfile caller = profileRepository.findByUserId(senderId).orElse(null);
            Map<String, Object> incoming = new LinkedHashMap<>();
            incoming.put("type", "voice_call_incoming");
            incoming.put("fromPlayerId", senderId.toString());
            incoming.put("fromPlayerName", caller == null ? "Buddy" : caller.getDisplayName());
            incoming.put("callId", callId);
            incoming.put("withVideo", payload.path("withVideo").asBoolean(false));
            incoming.put("targetPlayerId", targetId.toString());
            if (!publishVoiceEvent(session, incoming)) return;
            return;
        }

        if (!switch (type) {
            case "voice_call_accept", "voice_call_decline", "voice_call_offer",
                    "voice_call_answer", "voice_call_ice", "voice_call_end",
                    "voice_video_request", "voice_video_accept", "voice_video_decline",
                    "voice_video_offer", "voice_video_answer", "voice_video_ice" -> true;
            default -> false;
        }) {
            sendError(session, "VOICE_UNKNOWN_MESSAGE", "Unsupported voice-call message.");
            return;
        }

        Map<String, Object> relayed = new LinkedHashMap<>();
        relayed.put("type", type);
        relayed.put("fromPlayerId", senderId.toString());
        relayed.put("targetPlayerId", targetId.toString());
        relayed.put("callId", callId);
        if (payload.has("audioOnly")) {
            relayed.put("audioOnly", payload.path("audioOnly").asBoolean());
        }
        if (payload.has("description")) {
            relayed.put("description", objectMapper.convertValue(
                    payload.get("description"), Map.class));
        }
        if (payload.has("candidate")) {
            relayed.put("candidate", objectMapper.convertValue(
                    payload.get("candidate"), Map.class));
        }
        publishVoiceEvent(session, relayed);
    }

    public void routeRealtimeEvent(JsonNode event) {
        UUID targetId = parsePlayerId(event.path("targetPlayerId").asText(null));
        if (targetId == null) return;
        WebSocketSession recipient = sessions.get(targetId);
        if (recipient == null || !recipient.isOpen()) return;
        send(recipient, objectMapper.convertValue(event, Map.class));
    }

    private boolean publishVoiceEvent(WebSocketSession sender,
                                      Map<String, Object> voiceEvent) throws IOException {
        // On a single-instance deployment, route locally without waiting for or depending
        // on the database event channel. Multi-instance deployments fan out through PostgreSQL.
        if (routeLocally(voiceEvent)) return true;
        try {
            realtimeEvents.publish(Map.of(
                    "route", "voice",
                    "payload", voiceEvent));
            return true;
        } catch (RuntimeException exception) {
            log.warn("Could not publish voice event across instances: {}", exception.getMessage());
            sendError(sender, "VOICE_SIGNALING_UNAVAILABLE",
                    "Cross-device calling is temporarily unavailable. Try again shortly.");
            return false;
        }
    }

    @Scheduled(fixedDelayString = "${voice.presence.refresh-millis:15000}")
    public void refreshPresence() {
        sessions.forEach((playerId, session) -> {
            if (!session.isOpen()) removeSession(playerId, session);
        });
    }

    private void removeSession(UUID playerId, WebSocketSession session) {
        sessions.computeIfPresent(playerId, (ignored, active) ->
                active.getId().equals(session.getId()) ? null : active);
        presenceService.disconnected(playerId, "voice:" + session.getId());
    }

    private boolean routeLocally(Map<String, Object> event) {
        Object targetValue = event.get("targetPlayerId");
        UUID targetId = parsePlayerId(targetValue == null ? null : targetValue.toString());
        if (targetId == null) return false;
        WebSocketSession recipient = sessions.get(targetId);
        if (recipient == null || !recipient.isOpen()) return false;
        send(recipient, event);
        return true;
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        UUID playerId = (UUID) session.getAttributes().get(PLAYER_ATTRIBUTE);
        if (playerId != null) removeSession(playerId, session);
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
