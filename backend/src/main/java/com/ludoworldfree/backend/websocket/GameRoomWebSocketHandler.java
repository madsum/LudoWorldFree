package com.ludoworldfree.backend.websocket;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.service.MatchmakingService;
import com.ludoworldfree.backend.service.MatchmakingService.RoomSnapshot;
import com.ludoworldfree.backend.service.OnlineMatchChatService;
import com.ludoworldfree.backend.model.OnlineMatchStateEvent;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import org.springframework.web.util.UriComponentsBuilder;

import java.io.IOException;
import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class GameRoomWebSocketHandler extends TextWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(GameRoomWebSocketHandler.class);
    private static final int MAX_MESSAGE_CHARS = 64_000;
    private static final String ROOM_ATTRIBUTE = "gameRoomId";
    private static final String PLAYER_ATTRIBUTE = "gamePlayerId";
    private static final Set<String> GAME_EMOJIS = Set.of(
            "😀", "😂", "😎", "😡", "😭", "👑", "💣", "🎲", "👍", "🌵",
            "🤔", "😮", "❤️", "😘", "💋", "🔪", "mjolnir", "🎉", "🥳", "😴", "👏");

    private final ObjectMapper objectMapper;
    private final MatchmakingService matchmakingService;
    private final OnlineMatchChatService onlineMatchChatService;
    private final Map<String, LocalRoom> localRooms = new ConcurrentHashMap<>();

    public GameRoomWebSocketHandler(ObjectMapper objectMapper,
                                    MatchmakingService matchmakingService,
                                    OnlineMatchChatService onlineMatchChatService) {
        this.objectMapper = objectMapper;
        this.matchmakingService = matchmakingService;
        this.onlineMatchChatService = onlineMatchChatService;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws IOException {
        URI uri = session.getUri();
        String roomId = queryParameter(uri, "roomId");
        UUID playerId = resolvePlayerId(queryParameter(uri, "playerId"));
        String matchmakingSessionId = queryParameter(uri, "sessionId");
        if (roomId == null || playerId == null
                || !matchmakingService.isPlayerInRoom(
                        playerId, roomId, matchmakingSessionId)) {
            sendError(session, "MATCH_NOT_FOUND", "This player is not part of that match.");
            session.close(CloseStatus.POLICY_VIOLATION);
            return;
        }

        RoomSnapshot snapshot;
        try {
            snapshot = matchmakingService.connectPlayer(roomId, playerId);
        } catch (RuntimeException exception) {
            sendError(session, "ROOM_JOIN_FAILED", "This player cannot join that room.");
            session.close(CloseStatus.POLICY_VIOLATION);
            return;
        }

        session.getAttributes().put(ROOM_ATTRIBUTE, roomId);
        session.getAttributes().put(PLAYER_ATTRIBUTE, playerId);
        LocalRoom localRoom = localRooms.computeIfAbsent(roomId, LocalRoom::new);
        synchronized (localRoom) {
            long lastRematchRevision = snapshot.rematchRevision();
            if (snapshot.rematchStatus() ==
                    com.ludoworldfree.backend.model.OnlineMatchRoom.RematchStatus.REQUESTED
                    || (snapshot.rematchStatus() ==
                            com.ludoworldfree.backend.model.OnlineMatchRoom.RematchStatus.ACCEPTED
                            && snapshot.latestStateJson() == null)) {
                lastRematchRevision = Math.max(0, lastRematchRevision - 1);
            }
            LocalConnection connection = new LocalConnection(session, playerId,
                    snapshot.stateRevision(),
                    snapshot.allOtherPlayersConnected(playerId));
            connection.lastRematchRevision = lastRematchRevision;
            LocalConnection previousConnection = localRoom.sessions.put(playerId, connection);
            if (previousConnection != null && previousConnection.session != session
                    && previousConnection.session.isOpen()) {
                previousConnection.session.close(CloseStatus.NORMAL);
            }
            send(session, Map.of("type", "room_joined", "roomId", roomId));
            if (snapshot.status() == com.ludoworldfree.backend.model.OnlineMatchRoom.Status.READY) {
                broadcastRoomReady(localRoom, roomId);
                if (snapshot.stateRevision() > 0 && snapshot.latestStateJson() != null) {
                    sendState(session, snapshot.latestStateSenderId(),
                            snapshot.stateRevision(), snapshot.latestStateJson());
                }
            } else {
                send(session, Map.of("type", "room_waiting", "roomId", roomId));
            }
        }
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws IOException {
        if (message.getPayloadLength() > MAX_MESSAGE_CHARS) {
            sendError(session, "MESSAGE_TOO_LARGE", "The game update was too large.");
            session.close(CloseStatus.TOO_BIG_TO_PROCESS);
            return;
        }
        String roomId = (String) session.getAttributes().get(ROOM_ATTRIBUTE);
        UUID playerId = (UUID) session.getAttributes().get(PLAYER_ATTRIBUTE);
        if (roomId == null || playerId == null) {
            sendError(session, "NOT_JOINED", "Join a game room before sending updates.");
            return;
        }

        JsonNode payload;
        try {
            payload = objectMapper.readTree(message.getPayload());
        } catch (Exception exception) {
            sendError(session, "INVALID_JSON", "The game update was not valid JSON.");
            return;
        }
        String type = payload.path("type").asText();
        LocalRoom localRoom = localRooms.get(roomId);
        if (localRoom == null) return;

        switch (type) {
            case "game_state" -> recordGameState(session, localRoom, roomId, playerId, payload.get("state"));
            case "state_sync_request" -> sendCurrentGameState(session, roomId, playerId);
            case "roll_request" -> issueDiceRoll(session, roomId, playerId, payload);
            case "forfeit_disconnected" -> forfeitDisconnectedPlayer(
                    session, localRoom, roomId, playerId, payload);
            case "chat" -> relayChatMessage(session, localRoom, playerId, payload);
            case "chat_typing" -> relayChatTyping(session, localRoom, playerId, payload);
            case "emoji_reaction" -> relayEmojiReaction(session, localRoom, playerId, payload);
            case "dice_timer_stop_request" -> requestDiceTimerStop(
                    session, localRoom, playerId, payload);
            case "dice_timer_stop_response" -> respondToDiceTimerStop(
                    session, localRoom, playerId, payload);
            case "bell_alert" -> relayBellAlert(session, localRoom, playerId, payload);
            case "rematch_request" -> requestRematch(session, localRoom, roomId, playerId);
            case "rematch_response" -> respondToRematch(
                    session, localRoom, roomId, playerId, payload);
            case "ping" -> {
                matchmakingService.touchPlayer(roomId, playerId);
                send(session, Map.of("type", "pong"));
            }
            case "leave" -> finishRoomFromConnection(
                    session, localRoom, roomId, playerId);
            default -> sendError(session, "UNKNOWN_MESSAGE", "Unsupported game message type.");
        }
    }

    private void finishRoomFromConnection(WebSocketSession session, LocalRoom localRoom,
                                          String roomId, UUID playerId) {
        synchronized (localRoom) {
            LocalConnection connection = localRoom.sessions.get(playerId);
            if (connection == null || connection.session != session) return;
        }
        RoomSnapshot snapshot = matchmakingService.forfeitPlayerLeaving(roomId, playerId);
        if (snapshot != null && snapshot.latestStateJson() != null) {
            publishGameStateToLocal(localRoom, snapshot.latestStateSenderId(),
                    snapshot.stateRevision(), snapshot.latestStateJson());
        }
        closeLocalRoom(roomId, localRoom, Map.of(
                "type", "match_finished",
                "roomId", roomId,
                "playerId", playerId.toString(),
                "reason", "opponent_left"));
    }

    private void relayChatMessage(WebSocketSession session, LocalRoom localRoom,
                                  UUID playerId, JsonNode payload) {
        String text = payload.path("text").asText("").strip();
        if (text.isEmpty() || text.length() > 200) {
            sendError(session, "INVALID_CHAT", "Chat messages must be between 1 and 200 characters.");
            return;
        }

        synchronized (localRoom) {
            LocalConnection sender = localRoom.sessions.get(playerId);
            if (sender == null || sender.session != session) return;
            onlineMatchChatService.save(localRoom.id, playerId, text);
            relayChatEvents(localRoom);
        }
    }

    private void relayChatTyping(WebSocketSession session, LocalRoom localRoom,
                                 UUID playerId, JsonNode payload) {
        boolean isTyping = payload.path("isTyping").asBoolean(false);
        synchronized (localRoom) {
            LocalConnection sender = localRoom.sessions.get(playerId);
            if (sender == null || sender.session != session) return;
            onlineMatchChatService.saveTypingStatus(localRoom.id, playerId, isTyping);
            relayChatEvents(localRoom);
        }
    }

    private void relayEmojiReaction(WebSocketSession session, LocalRoom localRoom,
                                    UUID playerId, JsonNode payload) {
        String emoji = payload.path("emoji").asText("");
        UUID targetPlayerId = parsePlayerId(payload.path("targetPlayerId").asText(null));
        if (!GAME_EMOJIS.contains(emoji) || targetPlayerId == null ||
                targetPlayerId.equals(playerId)) {
            sendError(session, "INVALID_EMOJI", "Choose an emoji and a valid opponent.");
            return;
        }
        synchronized (localRoom) {
            LocalConnection sender = localRoom.sessions.get(playerId);
            if (sender == null || sender.session != session) return;
            LocalConnection target = localRoom.sessions.get(targetPlayerId);
            if (target == null) return;
            Map<String, Object> reaction = Map.of(
                    "type", "emoji_reaction",
                    "playerId", playerId.toString(),
                    "targetPlayerId", targetPlayerId.toString(),
                    "emoji", emoji);
            send(target.session, reaction);
        }
    }

    private void requestDiceTimerStop(WebSocketSession session, LocalRoom localRoom,
                                      UUID playerId, JsonNode payload) {
        String requesterName = payload.path("requesterName").asText("Player").strip();
        if (requesterName.isEmpty()) requesterName = "Player";
        if (requesterName.length() > 40) requesterName = requesterName.substring(0, 40);
        synchronized (localRoom) {
            LocalConnection sender = localRoom.sessions.get(playerId);
            if (sender == null || sender.session != session) return;
            RoomSnapshot snapshot = matchmakingService.getRoomSnapshot(localRoom.id);
            boolean hasRecipient = snapshot != null && snapshot.playerIds().stream()
                    .anyMatch(otherId -> !otherId.equals(playerId)
                            && snapshot.isConnected(otherId));
            if (!hasRecipient) {
                sendError(session, "DICE_TIMER_REQUEST_UNAVAILABLE",
                        "No other player is connected to receive this request.");
                return;
            }
            try {
                String request = objectMapper.writeValueAsString(Map.of(
                        "type", "dice_timer_stop_requested",
                        "requestId", UUID.randomUUID().toString(),
                        "requesterName", requesterName,
                        "expiresAt", System.currentTimeMillis() + 60_000));
                onlineMatchChatService.saveControlEvent(localRoom.id, playerId, request);
                send(sender.session, Map.of("type", "dice_timer_stop_request_sent"));
                relayChatEvents(localRoom);
            } catch (Exception exception) {
                sendError(session, "DICE_TIMER_REQUEST_FAILED",
                        "The dice timer stop request could not be sent.");
            }
        }
    }

    private void respondToDiceTimerStop(WebSocketSession session, LocalRoom localRoom,
                                        UUID playerId, JsonNode payload) {
        String requestId = payload.path("requestId").asText("");
        String requesterPlayerId = payload.path("requesterPlayerId").asText("");
        long expiresAt = payload.path("expiresAt").asLong(0);
        if (requestId.isBlank() || !payload.path("accept").isBoolean()
                || expiresAt < System.currentTimeMillis()) return;
        synchronized (localRoom) {
            LocalConnection responder = localRoom.sessions.get(playerId);
            UUID requesterId = parsePlayerId(requesterPlayerId);
            if (responder == null || responder.session != session || requesterId == null
                    || requesterId.equals(playerId)
                    || !matchmakingService.isPlayerInRoom(requesterId, localRoom.id)) return;
            try {
                String response = objectMapper.writeValueAsString(Map.of(
                        "type", "dice_timer_stop_response",
                        "requestId", requestId,
                        "requesterPlayerId", requesterId.toString(),
                        "accept", payload.path("accept").asBoolean(),
                        "expiresAt", expiresAt));
                onlineMatchChatService.saveControlEvent(localRoom.id, playerId, response);
                relayChatEvents(localRoom);
            } catch (Exception exception) {
                sendError(session, "DICE_TIMER_RESPONSE_FAILED",
                        "The dice timer stop response could not be sent.");
            }
        }
    }

    private void relayBellAlert(WebSocketSession session, LocalRoom localRoom,
                                UUID playerId, JsonNode payload) {
        UUID targetPlayerId = parsePlayerId(payload.path("targetPlayerId").asText(null));
        if (targetPlayerId == null || targetPlayerId.equals(playerId)) return;

        RoomSnapshot snapshot = matchmakingService.getRoomSnapshot(localRoom.id);
        if (snapshot == null || snapshot.status() !=
                com.ludoworldfree.backend.model.OnlineMatchRoom.Status.READY
                || !isActiveBellTarget(snapshot.latestStateJson(), targetPlayerId)) {
            return;
        }

        synchronized (localRoom) {
            LocalConnection sender = localRoom.sessions.get(playerId);
            LocalConnection recipient = localRoom.sessions.get(targetPlayerId);
            if (sender == null || sender.session != session || recipient == null) return;
            send(recipient.session, Map.of(
                    "type", "bell_alert",
                    "senderPlayerId", playerId.toString(),
                    "targetPlayerId", targetPlayerId.toString(),
                    "sentAt", System.currentTimeMillis()));
        }
    }

    private boolean isActiveBellTarget(String stateJson, UUID targetPlayerId) {
        if (stateJson == null) return false;
        try {
            JsonNode state = objectMapper.readTree(stateJson);
            if (state.path("isGameOver").asBoolean()) return false;
            for (JsonNode player : state.path("players")) {
                if (targetPlayerId.toString().equals(player.path("id").asText())) {
                    return !player.path("isEliminated").asBoolean();
                }
            }
        } catch (Exception exception) {
            return false;
        }
        return false;
    }

    private void issueDiceRoll(WebSocketSession session, String roomId, UUID playerId,
                               JsonNode payload) {
        int opportunityId = payload.path("rollOpportunityId").asInt(-1);
        try {
            int diceValue = matchmakingService.issueDiceRoll(roomId, playerId, opportunityId);
            send(session, Map.of("type", "dice_roll",
                    "rollOpportunityId", opportunityId, "value", diceValue));
        } catch (RuntimeException exception) {
            sendError(session, "ROLL_REJECTED", "The server rejected this dice roll request.");
        }
    }

    private void sendCurrentGameState(WebSocketSession session, String roomId, UUID playerId) {
        RoomSnapshot snapshot = matchmakingService.getRoomSnapshot(roomId);
        if (snapshot == null
                || snapshot.status() != com.ludoworldfree.backend.model.OnlineMatchRoom.Status.READY
                || !snapshot.playerIds().contains(playerId)
                || playerId.equals(snapshot.latestStateSenderId())
                || snapshot.latestStateJson() == null) {
            return;
        }
        try {
            Object state = objectMapper.readValue(snapshot.latestStateJson(), Object.class);
            send(session, Map.of(
                    "type", "game_state_sync",
                    "revision", snapshot.stateRevision(),
                    "state", state));
        } catch (Exception exception) {
            sendError(session, "STATE_SYNC_FAILED", "The current game state could not be read.");
        }
    }

    private void forfeitDisconnectedPlayer(WebSocketSession session, LocalRoom localRoom,
                                           String roomId, UUID playerId, JsonNode payload) {
        UUID disconnectedPlayerId = parsePlayerId(
                payload.path("disconnectedPlayerId").asText(null));
        if (disconnectedPlayerId == null || disconnectedPlayerId.equals(playerId)) return;
        synchronized (localRoom) {
            LocalConnection requester = localRoom.sessions.get(playerId);
            if (requester == null || requester.session != session) return;
        }
        try {
            RoomSnapshot snapshot = matchmakingService.forfeitDisconnectedPlayer(
                    roomId, playerId, disconnectedPlayerId);
            publishGameStateToLocal(localRoom, disconnectedPlayerId,
                    snapshot.stateRevision(), snapshot.latestStateJson());
        } catch (RuntimeException exception) {
            log.warn("Could not forfeit disconnected player {} in room {}: {}",
                    disconnectedPlayerId, roomId, exception.getMessage());
            sendError(session, "FORFEIT_REJECTED",
                    "The disconnected opponent could not be forfeited.");
        }
    }

    private void requestRematch(WebSocketSession session, LocalRoom localRoom,
                                String roomId, UUID playerId) {
        synchronized (localRoom) {
            LocalConnection connection = localRoom.sessions.get(playerId);
            if (connection == null || connection.session != session) return;
        }
        try {
            publishRematchUpdate(localRoom,
                    matchmakingService.requestRematch(roomId, playerId));
        } catch (RuntimeException exception) {
            String reason = exception.getMessage();
            log.warn("Replay request rejected for room {} player {}: {}",
                    roomId, playerId, reason, exception);
            sendError(session, "REMATCH_REJECTED", reason == null || reason.isBlank()
                    ? "The replay request could not be started." : reason);
        }
    }

    private void respondToRematch(WebSocketSession session, LocalRoom localRoom, String roomId,
                                  UUID playerId, JsonNode payload) {
        synchronized (localRoom) {
            LocalConnection connection = localRoom.sessions.get(playerId);
            if (connection == null || connection.session != session) return;
        }
        UUID roundId = parsePlayerId(payload.path("roundId").asText(null));
        if (roundId == null || !payload.path("accept").isBoolean()) {
            sendError(session, "INVALID_REMATCH_RESPONSE", "A replay response is required.");
            return;
        }
        try {
            publishRematchUpdate(localRoom, matchmakingService.respondToRematch(
                    roomId, playerId, roundId, payload.path("accept").asBoolean()));
        } catch (RuntimeException exception) {
            String reason = exception.getMessage();
            log.warn("Replay response rejected for room {} player {}: {}",
                    roomId, playerId, reason, exception);
            sendError(session, "REMATCH_REJECTED", reason == null || reason.isBlank()
                    ? "This replay request is no longer active." : reason);
        }
    }

    private void recordGameState(WebSocketSession session, LocalRoom localRoom,
                                 String roomId, UUID playerId, JsonNode state) throws IOException {
        if (state == null || !state.isObject()) {
            sendError(session, "INVALID_STATE", "A game state object is required.");
            return;
        }
        UUID activePlayerId = activePlayerId(state);
        Set<UUID> statePlayerIds = statePlayerIds(state);
        int rollOpportunityId = state.path("rollOpportunityId").asInt(-1);
        Integer diceValue = state.path("diceValue").isInt()
                ? state.path("diceValue").asInt() : null;
        boolean isDiceRolling = state.path("isDiceRolling").asBoolean(false);
        if (activePlayerId == null || (statePlayerIds.size() != 2 && statePlayerIds.size() != 4)) {
            sendError(session, "INVALID_STATE", "The game state must contain every matched player.");
            return;
        }

        RoomSnapshot snapshot;
        try {
            snapshot = matchmakingService.recordGameState(
                    roomId, playerId, statePlayerIds, activePlayerId,
                    rollOpportunityId, diceValue, isDiceRolling,
                    objectMapper.writeValueAsString(state));
        } catch (RuntimeException exception) {
            log.warn("Rejected game state for room {} player {}: {}",
                    roomId, playerId, exception.getMessage());
            sendError(session, "OUT_OF_TURN", "This player cannot submit the current game state.");
            return;
        }

        publishGameStateToLocal(localRoom, playerId, snapshot.stateRevision(),
                snapshot.latestStateJson());
    }

    private void publishGameStateToLocal(LocalRoom localRoom, UUID senderId,
                                         long revision, String stateJson) {
        synchronized (localRoom) {
            for (LocalConnection connection : localRoom.sessions.values()) {
                if (revision <= connection.lastRevision) continue;
                connection.lastRevision = revision;
                if (connection.playerId.equals(senderId)) continue;
                sendState(connection.session, senderId, revision, stateJson);
            }
        }
    }

    @Scheduled(fixedDelayString = "${game.rooms.poll-interval-ms:250}")
    public void relaySharedRoomState() {
        log.debug("relaySharedRoomState running, active rooms: {}", localRooms.size());
        for (Map.Entry<String, LocalRoom> entry : new ArrayList<>(localRooms.entrySet())) {
            String roomId = entry.getKey();
            LocalRoom localRoom = entry.getValue();
            RoomSnapshot snapshot = matchmakingService.getRoomSnapshot(roomId);
            if (snapshot == null || snapshot.status() ==
                    com.ludoworldfree.backend.model.OnlineMatchRoom.Status.CANCELLED) {
                closeLocalRoom(roomId, localRoom, Map.of(
                        "type", "match_finished", "roomId", roomId,
                        "reason", "room_closed"));
                continue;
            }

            if (snapshot.status() == com.ludoworldfree.backend.model.OnlineMatchRoom.Status.FINISHED) {
                relayStateEvents(localRoom, snapshot);
                closeLocalRoom(roomId, localRoom, Map.of(
                        "type", "match_finished", "roomId", roomId,
                        "reason", "room_closed"));
                continue;
            }

            publishRematchUpdate(localRoom, snapshot);

            synchronized (localRoom) {
                if (snapshot.status() == com.ludoworldfree.backend.model.OnlineMatchRoom.Status.READY
                        && !localRoom.readyNotified) {
                    broadcastRoomReady(localRoom, roomId);
                }
                for (LocalConnection connection : localRoom.sessions.values()) {
                    boolean opponentsConnected = snapshot.allOtherPlayersConnected(connection.playerId);
                    if (opponentsConnected != connection.opponentConnected) {
                        connection.opponentConnected = opponentsConnected;
                        if (opponentsConnected) {
                            send(connection.session, Map.of(
                                    "type", "connection_restored",
                                    "playerId", String.valueOf(connection.disconnectedPlayerId)));
                            connection.disconnectedPlayerId = null;
                        } else {
                            connection.disconnectedPlayerId = snapshot.playerIds().stream()
                                    .filter(id -> !id.equals(connection.playerId))
                                    .filter(id -> !snapshot.isConnected(id))
                                    .findFirst().orElse(null);
                            send(connection.session, Map.of(
                                    "type", "player_disconnected",
                                    "playerId", String.valueOf(connection.disconnectedPlayerId)));
                        }
                    }

                    if (snapshot.stateRevision() <= connection.lastRevision) continue;
                    List<OnlineMatchStateEvent> events = matchmakingService.getRoomEventsSince(
                            roomId, connection.lastRevision);
                    for (OnlineMatchStateEvent event : events) {
                        connection.lastRevision = event.getRevision();
                        if (connection.playerId.equals(event.getSenderId())) continue;
                        sendState(connection.session, event.getSenderId(),
                                event.getRevision(), event.getStateJson());
                    }
                }
            }
        }
    }

    @Scheduled(fixedDelayString = "${game.chat.poll-interval-ms:100}")
    public void relaySharedChatEvents() {
        for (LocalRoom localRoom : new ArrayList<>(localRooms.values())) {
            synchronized (localRoom) {
                if (!localRoom.sessions.isEmpty()) relayChatEvents(localRoom);
            }
        }
    }

    private void relayChatEvents(LocalRoom localRoom) {
        List<OnlineMatchChatService.ChatEvent> events = onlineMatchChatService.after(
                localRoom.id, localRoom.lastChatEventId);
        for (OnlineMatchChatService.ChatEvent event : events) {
            localRoom.lastChatEventId = event.id();
            if (event.eventType().startsWith("TYPING_")) {
                broadcast(localRoom, Map.of(
                        "type", "chat_typing",
                        "playerId", event.playerId().toString(),
                        "isTyping", "TYPING_START".equals(event.eventType())));
                continue;
            }
            if ("GAME_CONTROL".equals(event.eventType())) {
                relayGameControlEvent(localRoom, event);
                continue;
            }
            Map<String, Object> chat = Map.of(
                    "type", "chat",
                    "playerId", event.playerId().toString(),
                    "text", event.text(),
                    "sentAt", event.createdAt().toEpochMilli());
            broadcast(localRoom, chat);
        }
    }

    private void relayGameControlEvent(LocalRoom localRoom,
                                       OnlineMatchChatService.ChatEvent event) {
        try {
            JsonNode payload = objectMapper.readTree(event.text());
            String type = payload.path("type").asText("");
            if (payload.path("expiresAt").asLong(0) < System.currentTimeMillis()) return;
            if ("dice_timer_stop_requested".equals(type)) {
                Map<String, Object> request = objectMapper.convertValue(payload, Map.class);
                request.put("requesterPlayerId", event.playerId().toString());
                for (LocalConnection connection : localRoom.sessions.values()) {
                    if (!connection.playerId.equals(event.playerId())) {
                        send(connection.session, request);
                    }
                }
            } else if ("dice_timer_stop_response".equals(type)) {
                boolean accepted = payload.path("accept").asBoolean(false);
                Map<String, Object> response = objectMapper.convertValue(payload, Map.class);
                response.put("type", accepted
                        ? "dice_timer_stop_accepted" : "dice_timer_stop_declined");
                response.put("responderPlayerId", event.playerId().toString());
                if (accepted) {
                    broadcast(localRoom, response);
                } else {
                    UUID requesterId = parsePlayerId(
                            payload.path("requesterPlayerId").asText(null));
                    LocalConnection requester = requesterId == null
                            ? null : localRoom.sessions.get(requesterId);
                    if (requester != null) send(requester.session, response);
                }
            }
        } catch (Exception exception) {
            log.warn("Could not relay a game control event in room {}: {}",
                    localRoom.id, exception.getMessage());
        }
    }

    private void relayStateEvents(LocalRoom localRoom, RoomSnapshot snapshot) {
        synchronized (localRoom) {
            for (LocalConnection connection : localRoom.sessions.values()) {
                if (snapshot.stateRevision() <= connection.lastRevision) continue;
                List<OnlineMatchStateEvent> events = matchmakingService.getRoomEventsSince(
                        snapshot.roomId(), connection.lastRevision);
                for (OnlineMatchStateEvent event : events) {
                    connection.lastRevision = event.getRevision();
                    if (connection.playerId.equals(event.getSenderId())) continue;
                    sendState(connection.session, event.getSenderId(),
                            event.getRevision(), event.getStateJson());
                }
            }
        }
    }

    private void publishRematchUpdate(LocalRoom localRoom, RoomSnapshot snapshot) {
        synchronized (localRoom) {
            for (LocalConnection connection : localRoom.sessions.values()) {
                if (snapshot.rematchRevision() <= connection.lastRematchRevision) continue;
                connection.lastRematchRevision = snapshot.rematchRevision();
                if (snapshot.rematchStatus() ==
                        com.ludoworldfree.backend.model.OnlineMatchRoom.RematchStatus.ACCEPTED) {
                    // Drop any undelivered events from the completed game. The
                    // first state after this baseline is the clean replay state.
                    connection.lastRevision = Math.max(
                            connection.lastRevision, snapshot.stateRevision());
                }
                send(connection.session, Map.of(
                        "type", "rematch_update",
                        "revision", snapshot.rematchRevision(),
                        "roundId", snapshot.rematchRoundId() == null
                                ? "" : snapshot.rematchRoundId().toString(),
                        "requesterId", snapshot.rematchRequesterId() == null
                                ? "" : snapshot.rematchRequesterId().toString(),
                        "status", snapshot.rematchStatus().name(),
                        "acceptedPlayerIds", snapshot.rematchAcceptedPlayerIds().stream()
                                .map(UUID::toString).toList()));
            }
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        String roomId = (String) session.getAttributes().get(ROOM_ATTRIBUTE);
        UUID playerId = (UUID) session.getAttributes().get(PLAYER_ATTRIBUTE);
        if (roomId == null || playerId == null) return;
        LocalRoom localRoom = localRooms.get(roomId);
        boolean currentConnection = false;
        if (localRoom != null) {
            synchronized (localRoom) {
                LocalConnection connection = localRoom.sessions.get(playerId);
                if (connection != null && connection.session == session) {
                    localRoom.sessions.remove(playerId);
                    currentConnection = true;
                }
                if (localRoom.sessions.isEmpty()) localRooms.remove(roomId, localRoom);
            }
        }
        if (currentConnection) matchmakingService.disconnectPlayer(roomId, playerId);
    }

    private void broadcastRoomReady(LocalRoom room, String roomId) {
        room.readyNotified = true;
        broadcast(room, Map.of("type", "room_ready", "roomId", roomId));
    }

    private void closeLocalRoom(String roomId, LocalRoom room, Map<String, Object> payload) {
        synchronized (room) {
            broadcast(room, payload);
            for (LocalConnection connection : room.sessions.values()) {
                try { connection.session.close(CloseStatus.NORMAL); }
                catch (IOException ignored) {}
            }
            room.sessions.clear();
            localRooms.remove(roomId, room);
        }
    }

    private void broadcast(LocalRoom room, Map<String, Object> payload) {
        for (LocalConnection connection : room.sessions.values()) send(connection.session, payload);
    }

    private void send(WebSocketSession session, Map<String, Object> payload) {
        if (session == null || !session.isOpen()) return;
        try {
            synchronized (session) {
                session.sendMessage(new TextMessage(objectMapper.writeValueAsString(payload)));
            }
        } catch (IOException ignored) {
            try { session.close(CloseStatus.SERVER_ERROR); }
            catch (IOException ignoredClose) {}
        }
    }

    private void sendError(WebSocketSession session, String code, String detail) {
        send(session, Map.of("type", "error", "code", code, "message", detail));
    }

    private void sendState(WebSocketSession session, UUID playerId,
                           long revision, String stateJson) {
        if (playerId == null) return;
        try {
            Object state = objectMapper.readValue(stateJson, Object.class);
            send(session, Map.of(
                    "type", "game_state",
                    "playerId", playerId.toString(),
                    "revision", revision,
                    "state", state));
        } catch (Exception exception) {
            sendError(session, "INVALID_STATE", "A saved game update could not be read.");
        }
    }

    private static String queryParameter(URI uri, String name) {
        if (uri == null) return null;
        return UriComponentsBuilder.fromUri(uri).build().getQueryParams().getFirst(name);
    }

    private static UUID resolvePlayerId(String value) {
        if (value == null || value.isBlank()) return null;
        return PlayerIdResolver.resolve(value);
    }

    private static UUID parsePlayerId(String value) {
        try { return UUID.fromString(value); }
        catch (RuntimeException ignored) { return null; }
    }

    private static UUID activePlayerId(JsonNode state) {
        JsonNode players = state.path("players");
        int currentIndex = state.path("currentTurnIndex").asInt(-1);
        if (!players.isArray() || currentIndex < 0 || currentIndex >= players.size()) return null;
        return parsePlayerId(players.get(currentIndex).path("id").asText(null));
    }

    private static Set<UUID> statePlayerIds(JsonNode state) {
        JsonNode players = state.path("players");
        if (!players.isArray() || (players.size() != 2 && players.size() != 4)) return Set.of();
        Set<UUID> ids = ConcurrentHashMap.newKeySet();
        for (JsonNode player : players) {
            UUID id = parsePlayerId(player.path("id").asText(null));
            if (id == null) return Set.of();
            ids.add(id);
        }
        return ids.size() == players.size() ? ids : Set.of();
    }

    private static final class LocalRoom {
        private final String id;
        private final Map<UUID, LocalConnection> sessions = new ConcurrentHashMap<>();
        private boolean readyNotified;
        private long lastChatEventId;

        private LocalRoom(String id) { this.id = id; }
    }

    private static final class LocalConnection {
        private final WebSocketSession session;
        private final UUID playerId;
        private long lastRevision;
        private long lastRematchRevision;
        private boolean opponentConnected;
        private UUID disconnectedPlayerId;

        private LocalConnection(WebSocketSession session, UUID playerId,
                                long lastRevision, boolean opponentConnected) {
            this.session = session;
            this.playerId = playerId;
            this.lastRevision = lastRevision;
            this.opponentConnected = opponentConnected;
        }
    }
}
