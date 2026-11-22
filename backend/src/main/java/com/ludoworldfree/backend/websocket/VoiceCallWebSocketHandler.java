package com.ludoworldfree.backend.websocket;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.model.Friendship;
import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.repository.FriendshipRepository;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import com.ludoworldfree.backend.chat.ChatEventPublisher;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
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
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class VoiceCallWebSocketHandler extends TextWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(VoiceCallWebSocketHandler.class);
    private static final int MAX_MESSAGE_CHARS = 32_000;
    private static final String PLAYER_ATTRIBUTE = "voicePlayerId";
    private static final String PRESENCE_PREFIX = "ludoworld:voice:online:";
    private static final Duration PRESENCE_TTL = Duration.ofSeconds(45);

    private final ObjectMapper objectMapper;
    private final FriendshipRepository friendshipRepository;
    private final PlayerProfileRepository profileRepository;
    private final StringRedisTemplate redis;
    private final String instanceId = UUID.randomUUID().toString();
    private final Map<UUID, WebSocketSession> sessions = new ConcurrentHashMap<>();

    public VoiceCallWebSocketHandler(ObjectMapper objectMapper,
                                     FriendshipRepository friendshipRepository,
                                     PlayerProfileRepository profileRepository,
                                     StringRedisTemplate redis) {
        this.objectMapper = objectMapper;
        this.friendshipRepository = friendshipRepository;
        this.profileRepository = profileRepository;
        this.redis = redis;
    }

    public boolean isOnline(UUID playerId) {
        try {
            return Boolean.TRUE.equals(redis.hasKey(presenceKey(playerId)));
        } catch (RuntimeException exception) {
            WebSocketSession session = sessions.get(playerId);
            return session != null && session.isOpen();
        }
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
        redis.opsForValue().set(presenceKey(playerId), sessionMarker(decorated), PRESENCE_TTL);
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

    public void routeRedisEvent(JsonNode event) {
        UUID targetId = parsePlayerId(event.path("targetPlayerId").asText(null));
        if (targetId == null) return;
        WebSocketSession recipient = sessions.get(targetId);
        if (recipient == null || !recipient.isOpen()) return;
        try {
            if (!sessionMarker(recipient).equals(
                    redis.opsForValue().get(presenceKey(targetId)))) return;
        } catch (RuntimeException exception) {
            log.debug("Could not verify voice-session owner during routing: {}",
                    exception.getMessage());
        }
        send(recipient, objectMapper.convertValue(event, Map.class));
    }

    private boolean publishVoiceEvent(WebSocketSession sender,
                                      Map<String, Object> voiceEvent) throws IOException {
        try {
            String envelope = objectMapper.writeValueAsString(Map.of(
                    "route", "voice",
                    "payload", voiceEvent));
            Long subscriberCount = redis.convertAndSend(ChatEventPublisher.CHANNEL, envelope);
            if (subscriberCount == null || subscriberCount == 0) {
                routeRedisEvent(objectMapper.valueToTree(voiceEvent));
            }
            return true;
        } catch (RuntimeException exception) {
            log.warn("Could not route voice-call event across instances: {}",
                    exception.getMessage());
            sendError(sender, "VOICE_SIGNALING_UNAVAILABLE",
                    "Call signaling is temporarily unavailable. Try again shortly.");
            return false;
        }
    }

    @Scheduled(fixedDelayString = "${voice.presence.refresh-millis:15000}")
    public void refreshPresence() {
        sessions.forEach((playerId, session) -> {
            if (!session.isOpen()) {
                removeSession(playerId, session);
                return;
            }
            String key = presenceKey(playerId);
            String marker = sessionMarker(session);
            String owner = redis.opsForValue().get(key);
            if (owner == null) {
                redis.opsForValue().set(key, marker, PRESENCE_TTL);
            } else if (marker.equals(owner)) {
                redis.expire(key, PRESENCE_TTL);
            } else {
                try {
                    session.close(CloseStatus.NORMAL);
                } catch (IOException exception) {
                    log.debug("Could not close replaced voice session: {}", exception.getMessage());
                }
            }
        });
    }

    private void removeSession(UUID playerId, WebSocketSession session) {
        sessions.computeIfPresent(playerId, (ignored, active) ->
                active.getId().equals(session.getId()) ? null : active);
        String key = presenceKey(playerId);
        String marker = sessionMarker(session);
        if (marker.equals(redis.opsForValue().get(key))) redis.delete(key);
    }

    private String presenceKey(UUID playerId) {
        return PRESENCE_PREFIX + playerId;
    }

    private String sessionMarker(WebSocketSession session) {
        return instanceId + ":" + session.getId();
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
