package com.ludoworldfree.backend.websocket;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.service.MatchmakingService;
import com.ludoworldfree.backend.service.MatchmakingService.RoomSnapshot;
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

    private final ObjectMapper objectMapper;
    private final MatchmakingService matchmakingService;
    private final Map<String, LocalRoom> localRooms = new ConcurrentHashMap<>();

    public GameRoomWebSocketHandler(ObjectMapper objectMapper,
                                    MatchmakingService matchmakingService) {
        this.objectMapper = objectMapper;
        this.matchmakingService = matchmakingService;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws IOException {
        URI uri = session.getUri();
        String roomId = queryParameter(uri, "roomId");
        UUID playerId = resolvePlayerId(queryParameter(uri, "playerId"));
        if (roomId == null || playerId == null
                || !matchmakingService.isPlayerInRoom(playerId, roomId)) {
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
            LocalConnection connection = new LocalConnection(session, playerId,
                    snapshot.stateRevision(),
                    snapshot.allOtherPlayersConnected(playerId));
            LocalConnection previousConnection = localRoom.sessions.put(playerId, connection);
            if (previousConnection != null && previousConnection.session != session
                    && previousConnection.session.isOpen()) {
                previousConnection.session.close(CloseStatus.NORMAL);
            }
            send(session, Map.of("type", "room_joined", "roomId", roomId));
            if (snapshot.status() == com.ludoworldfree.backend.model.OnlineMatchRoom.Status.READY) {
                broadcastRoomReady(localRoom, roomId);
                if (snapshot.stateRevision() > 0 && snapshot.latestStateJson() != null) {
                    sendState(session, snapshot.latestStateSenderId(), snapshot.latestStateJson());
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
            case "roll_request" -> issueDiceRoll(session, roomId, playerId, payload);
            case "ping" -> {
                matchmakingService.touchPlayer(roomId, playerId);
                send(session, Map.of("type", "pong"));
            }
            case "leave" -> {
                matchmakingService.finishRoom(roomId);
                closeLocalRoom(roomId, localRoom, Map.of(
                        "type", "match_finished",
                        "playerId", playerId.toString(),
                        "reason", "opponent_left"));
            }
            default -> sendError(session, "UNKNOWN_MESSAGE", "Unsupported game message type.");
        }
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
            sendError(session, "OUT_OF_TURN", "This player cannot submit the current game state.");
            return;
        }

        synchronized (localRoom) {
            LocalConnection sender = localRoom.sessions.get(playerId);
            if (sender != null && sender.session == session) {
                sender.lastRevision = snapshot.stateRevision();
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
            if (snapshot == null || snapshot.status() == com.ludoworldfree.backend.model.OnlineMatchRoom.Status.FINISHED
                    || snapshot.status() == com.ludoworldfree.backend.model.OnlineMatchRoom.Status.CANCELLED) {
                closeLocalRoom(roomId, localRoom, Map.of(
                        "type", "match_finished", "reason", "room_closed"));
                continue;
            }

            synchronized (localRoom) {
                if (snapshot.status() == com.ludoworldfree.backend.model.OnlineMatchRoom.Status.READY
                        && !localRoom.readyNotified) {
                    broadcastRoomReady(localRoom, roomId);
                }
                for (LocalConnection connection : localRoom.sessions.values()) {
                    boolean opponentsConnected = snapshot.allOtherPlayersConnected(connection.playerId);
                    if (opponentsConnected != connection.opponentConnected) {
                        connection.opponentConnected = opponentsConnected;
                        send(connection.session, Map.of("type", opponentsConnected
                                ? "connection_restored" : "player_disconnected"));
                    }

                    if (snapshot.stateRevision() <= connection.lastRevision) continue;
                    List<OnlineMatchStateEvent> events = matchmakingService.getRoomEventsSince(
                            roomId, connection.lastRevision);
                    for (OnlineMatchStateEvent event : events) {
                        connection.lastRevision = event.getRevision();
                        if (connection.playerId.equals(event.getSenderId())) continue;
                        sendState(connection.session, event.getSenderId(), event.getStateJson());
                    }
                }
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

    private void sendState(WebSocketSession session, UUID playerId, String stateJson) {
        if (playerId == null) return;
        try {
            Object state = objectMapper.readValue(stateJson, Object.class);
            send(session, Map.of("type", "game_state", "playerId", playerId.toString(), "state", state));
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

        private LocalRoom(String id) { this.id = id; }
    }

    private static final class LocalConnection {
        private final WebSocketSession session;
        private final UUID playerId;
        private long lastRevision;
        private boolean opponentConnected;

        private LocalConnection(WebSocketSession session, UUID playerId,
                                long lastRevision, boolean opponentConnected) {
            this.session = session;
            this.playerId = playerId;
            this.lastRevision = lastRevision;
            this.opponentConnected = opponentConnected;
        }
    }
}
