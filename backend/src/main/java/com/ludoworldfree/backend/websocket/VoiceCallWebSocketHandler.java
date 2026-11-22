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
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

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
    private final AtomicBoolean redisUnavailableLogged = new AtomicBoolean();
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
        WebSocketSession localSession = sessions.get(playerId);
        if (localSession != null && localSession.isOpen()) return true;
        return onlineStatuses(List.of(playerId)).getOrDefault(playerId, false);
    }

    public Map<UUID, Boolean> onlineStatuses(Collection<UUID> playerIds) {
        Set<UUID> uniqueIds = new LinkedHashSet<>(playerIds);
        if (uniqueIds.isEmpty()) return Map.of();
        List<UUID> orderedIds = new ArrayList<>(uniqueIds);
        List<String> keys = orderedIds.stream().map(this::presenceKey).toList();
        try {
            List<String> owners = redis.opsForValue().multiGet(keys);
            Map<UUID, Boolean> statuses = new LinkedHashMap<>();
            for (int index = 0; index < orderedIds.size(); index++) {
                WebSocketSession localSession = sessions.get(orderedIds.get(index));
                statuses.put(orderedIds.get(index),
                        (owners != null && owners.get(index) != null)
                                || (localSession != null && localSession.isOpen()));
            }
            redisUnavailableLogged.set(false);
            return statuses;
        } catch (RuntimeException exception) {
            logRedisUnavailable(exception);
            Map<UUID, Boolean> statuses = new LinkedHashMap<>();
            for (UUID playerId : orderedIds) {
                WebSocketSession session = sessions.get(playerId);
                statuses.put(playerId, session != null && session.isOpen());
            }
            return statuses;
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
        try {
            redis.opsForValue().set(presenceKey(playerId), sessionMarker(decorated), PRESENCE_TTL);
            redisUnavailableLogged.set(false);
        } catch (RuntimeException exception) {
            logRedisUnavailable(exception);
        }
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
        // On a single-instance deployment, route locally without waiting for or depending
        // on Redis. Redis remains the fallback for deployments with multiple instances.
        if (routeLocally(voiceEvent)) return true;
        try {
            String envelope = objectMapper.writeValueAsString(Map.of(
                    "route", "voice",
                    "payload", voiceEvent));
            Long subscriberCount = redis.convertAndSend(ChatEventPublisher.CHANNEL, envelope);
            if (subscriberCount == null || subscriberCount == 0) {
                sendError(sender, "VOICE_SIGNALING_UNAVAILABLE",
                        "Call signaling has no active Redis route. Try again shortly.");
                return false;
            }
            redisUnavailableLogged.set(false);
            return true;
        } catch (RuntimeException exception) {
            logRedisUnavailable(exception);
            sendError(sender, "VOICE_SIGNALING_UNAVAILABLE",
                    "Cross-device calling needs the backend Redis connection. Try again shortly.");
            return false;
        }
    }

    @Scheduled(fixedDelayString = "${voice.presence.refresh-millis:15000}")
    public void refreshPresence() {
        try {
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
            redisUnavailableLogged.set(false);
        } catch (RuntimeException exception) {
            logRedisUnavailable(exception);
        }
    }

    private void removeSession(UUID playerId, WebSocketSession session) {
        sessions.computeIfPresent(playerId, (ignored, active) ->
                active.getId().equals(session.getId()) ? null : active);
        String key = presenceKey(playerId);
        String marker = sessionMarker(session);
        try {
            if (marker.equals(redis.opsForValue().get(key))) redis.delete(key);
        } catch (RuntimeException exception) {
            logRedisUnavailable(exception);
        }
    }

    private String presenceKey(UUID playerId) {
        return PRESENCE_PREFIX + playerId;
    }

    private String sessionMarker(WebSocketSession session) {
        return instanceId + ":" + session.getId();
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

    private void logRedisUnavailable(RuntimeException exception) {
        if (redisUnavailableLogged.compareAndSet(false, true)) {
            log.warn("Redis is unavailable; using same-instance voice fallback: {}",
                    exception.getMessage());
        }
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
