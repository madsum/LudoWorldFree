package com.ludoworldfree.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.dto.MatchmakingRequestDto;
import com.ludoworldfree.backend.dto.MatchmakingResponseDto;
import com.ludoworldfree.backend.model.GoldTransaction;
import com.ludoworldfree.backend.model.MatchmakingTicket;
import com.ludoworldfree.backend.model.OnlineMatchRoom;
import com.ludoworldfree.backend.model.OnlineMatchStateEvent;
import com.ludoworldfree.backend.model.PlayerWallet;
import com.ludoworldfree.backend.repository.GoldTransactionRepository;
import com.ludoworldfree.backend.repository.MatchmakingTicketRepository;
import com.ludoworldfree.backend.repository.OnlineMatchRoomRepository;
import com.ludoworldfree.backend.repository.OnlineMatchStateEventRepository;
import com.ludoworldfree.backend.repository.PlayerWalletRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.security.SecureRandom;

@Service
public class MatchmakingService {
    private static final Logger log = LoggerFactory.getLogger(MatchmakingService.class);
    private static final List<OnlineMatchRoom.Status> ACTIVE_STATUSES =
            List.of(OnlineMatchRoom.Status.MATCHED, OnlineMatchRoom.Status.READY);

    public record RoomSnapshot(
            String roomId,
            OnlineMatchRoom.Status status,
            List<UUID> playerIds,
            List<UUID> connectedPlayerIds,
            UUID turnOwnerId,
            long stateRevision,
            UUID latestStateSenderId,
            String latestStateJson) {
        public boolean isConnected(UUID playerId) {
            return connectedPlayerIds.contains(playerId);
        }

        public UUID opponentOf(UUID playerId) {
            int index = playerIds.indexOf(playerId);
            return index < 0 ? null : playerIds.get((index + 1) % playerIds.size());
        }

        public boolean allOtherPlayersConnected(UUID playerId) {
            return playerIds.stream().filter(id -> !id.equals(playerId)).allMatch(connectedPlayerIds::contains);
        }
    }

    private final MatchmakingTicketRepository ticketRepository;
    private final OnlineMatchRoomRepository roomRepository;
    private final OnlineMatchStateEventRepository stateEventRepository;
    private final PlayerWalletRepository walletRepository;
    private final GoldTransactionRepository transactionRepository;
    private final ObjectMapper objectMapper;
    private final SecureRandom diceRandom = new SecureRandom();

    public MatchmakingService(MatchmakingTicketRepository ticketRepository,
                              OnlineMatchRoomRepository roomRepository,
                              OnlineMatchStateEventRepository stateEventRepository,
                              PlayerWalletRepository walletRepository,
                              GoldTransactionRepository transactionRepository,
                              ObjectMapper objectMapper) {
        this.ticketRepository = ticketRepository;
        this.roomRepository = roomRepository;
        this.stateEventRepository = stateEventRepository;
        this.walletRepository = walletRepository;
        this.transactionRepository = transactionRepository;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public MatchmakingResponseDto joinQueue(MatchmakingRequestDto request) {
        UUID playerId = request.getPlayerId();
        if (playerId == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "A player ID is required.");
        }
        if (request.getEntryFee() < 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Entry fee cannot be negative.");
        }
        if (request.getPlayerCount() != 2 && request.getPlayerCount() != 4) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Choose two or four players.");
        }
        List<String> colors = List.of("red", "green", "yellow", "blue");
        String selectedColor = request.getSelectedColor() == null
                ? "red" : request.getSelectedColor().toLowerCase();
        if (!colors.contains(selectedColor)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Choose a valid player color.");
        }

        OnlineMatchRoom activeRoom = findActiveRoom(playerId);
        if (activeRoom != null) return responseFor(activeRoom, playerId);

        var existingTicket = ticketRepository.findByPlayerId(playerId);
        MatchmakingTicket currentTicket;
        if (existingTicket.isPresent()
                && existingTicket.get().getEntryFee() == request.getEntryFee()
                && existingTicket.get().getPlayerCount() == request.getPlayerCount()
                && existingTicket.get().getSelectedColor().equals(selectedColor)) {
            // A repeated join is also a matchmaking retry. This lets queued players
            // recover when concurrent first joins both observed an empty queue.
            currentTicket = existingTicket.get();
        } else {
            existingTicket.ifPresent(ticketRepository::delete);
            currentTicket = new MatchmakingTicket(
                    playerId,
                    nonBlank(request.getDisplayName(), "Player"),
                    request.getAvatarUrl(),
                    nonBlank(request.getCountry(), "World"),
                    nonBlank(request.getCountryFlag(), "🌐"),
                    request.getEntryFee(), request.getPlayerCount(), selectedColor);
        }

        List<MatchmakingTicket> candidates = ticketRepository.findWaitingCandidateForUpdate(
                request.getEntryFee(), request.getPlayerCount(), playerId,
                PageRequest.of(0, request.getPlayerCount() - 1));
        List<MatchmakingTicket> matchedTickets = selectCompatibleTickets(
                currentTicket, candidates);
        if (matchedTickets.isEmpty()) {
            PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                    .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));
            if (wallet.getBalance() < request.getEntryFee()) return insufficientFunds();
            ticketRepository.save(currentTicket);
            return searchingResponse();
        }

        List<MatchmakingTicket> allTickets = new ArrayList<>();
        allTickets.add(currentTicket);
        allTickets.addAll(matchedTickets);
        Map<UUID, PlayerWallet> wallets = lockWallets(allTickets.stream()
                .map(MatchmakingTicket::getPlayerId).toList());
        PlayerWallet currentWallet = wallets.get(playerId);
        if (currentWallet.getBalance() < request.getEntryFee()) return insufficientFunds();
        for (MatchmakingTicket ticket : matchedTickets) {
            if (wallets.get(ticket.getPlayerId()).getBalance() < request.getEntryFee()) {
                ticketRepository.delete(ticket);
                return requeueCurrentTicket(currentTicket);
            }
        }

        String roomId = UUID.randomUUID().toString();
        for (MatchmakingTicket ticket : allTickets) {
            deductEntryFee(wallets.get(ticket.getPlayerId()), request.getEntryFee(), roomId);
        }
        transactionRepository.flush();

        OnlineMatchRoom room = new OnlineMatchRoom(roomId, allTickets, request.getEntryFee());
        roomRepository.saveAndFlush(room);
        ticketRepository.deleteAll(matchedTickets);
        log.info("Online match {} created for {} players", roomId, allTickets.size());
        return responseFor(room, playerId);
    }

    private MatchmakingResponseDto requeueCurrentTicket(MatchmakingTicket ticket) {
        ticketRepository.save(ticket);
        return searchingResponse();
    }

    private List<MatchmakingTicket> selectCompatibleTickets(
            MatchmakingTicket current, List<MatchmakingTicket> candidates) {
        List<MatchmakingTicket> selected = new ArrayList<>();
        int needed = current.getPlayerCount() - 1;
        for (MatchmakingTicket candidate : candidates) {
            selected.add(candidate);
            if (selected.size() == needed) return selected;
        }
        return List.of();
    }

    @Transactional
    public MatchmakingResponseDto checkStatus(UUID playerId) {
        OnlineMatchRoom activeRoom = findActiveRoom(playerId);
        if (activeRoom != null) return responseFor(activeRoom, playerId);
        MatchmakingTicket ticket = ticketRepository.findByPlayerId(playerId).orElse(null);
        if (ticket != null) {
            MatchmakingRequestDto retry = new MatchmakingRequestDto(
                    playerId, ticket.getDisplayName(), ticket.getAvatarUrl(),
                    ticket.getCountry(), ticket.getCountryFlag(), ticket.getEntryFee());
            retry.setPlayerCount(ticket.getPlayerCount());
            retry.setSelectedColor(ticket.getSelectedColor());
            return joinQueue(retry);
        }
        return searchingResponse();
    }

    @Transactional(readOnly = true)
    public boolean isPlayerInRoom(UUID playerId, String roomId) {
        if (playerId == null || roomId == null) return false;
        return roomRepository.findById(roomId)
                .filter(room -> ACTIVE_STATUSES.contains(room.getStatus()) && room.contains(playerId))
                .isPresent();
    }

    @Transactional
    public void cancelQueue(UUID playerId) {
        ticketRepository.deleteById(playerId);
        List<OnlineMatchRoom> rooms = roomRepository.findActiveForPlayerForUpdate(
                playerId, ACTIVE_STATUSES);
        for (OnlineMatchRoom room : rooms) cancelOrFinish(room);
    }

    @Transactional
    public void finishRoom(String roomId) {
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId).orElse(null);
        if (room == null || room.getStatus() == OnlineMatchRoom.Status.FINISHED
                || room.getStatus() == OnlineMatchRoom.Status.CANCELLED) return;
        if (room.getStatus() == OnlineMatchRoom.Status.MATCHED) {
            refundRoom(room);
            room.cancel();
        } else {
            room.finish();
        }
        roomRepository.save(room);
    }

    @Transactional
    public RoomSnapshot connectPlayer(String roomId, UUID playerId) {
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Match room not found."));
        if (!room.contains(playerId) || !ACTIVE_STATUSES.contains(room.getStatus())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "This player cannot join that room.");
        }
        room.connect(playerId);
        return snapshot(roomRepository.save(room));
    }

    @Transactional
    public RoomSnapshot disconnectPlayer(String roomId, UUID playerId) {
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId).orElse(null);
        if (room == null || !room.contains(playerId)) return null;
        room.disconnect(playerId);
        return snapshot(roomRepository.save(room));
    }

    @Transactional(readOnly = true)
    public RoomSnapshot getRoomSnapshot(String roomId) {
        return roomRepository.findById(roomId).map(MatchmakingService::snapshot).orElse(null);
    }

    @Transactional(readOnly = true)
    public List<OnlineMatchStateEvent> getRoomEventsSince(String roomId, long revision) {
        return stateEventRepository.findByRoomIdAndRevisionGreaterThanOrderByRevisionAsc(
                roomId, revision);
    }

    @Transactional
    public RoomSnapshot recordGameState(String roomId, UUID senderId,
                                        Set<UUID> statePlayerIds,
                                        UUID nextTurnOwnerId,
                                        int rollOpportunityId,
                                        Integer diceValue,
                                        boolean isDiceRolling,
                                        String stateJson) {
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Match room not found."));
        Set<UUID> roomPlayerIds = Set.copyOf(room.getPlayerIds());
        if (room.getStatus() != OnlineMatchRoom.Status.READY
                || !roomPlayerIds.equals(statePlayerIds)
                || !senderId.equals(room.getTurnOwnerId())
                || !roomPlayerIds.contains(nextTurnOwnerId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "This player cannot submit the current game state.");
        }
        if (!isDiceRolling && diceValue != null
                && !room.matchesAuthoritativeRoll(senderId, rollOpportunityId, diceValue)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "The submitted dice result was not issued by the server.");
        }
        validatePawnTransition(room, senderId, nextTurnOwnerId, diceValue,
                rollOpportunityId, isDiceRolling, stateJson);
        room.recordState(senderId, nextTurnOwnerId, stateJson);
        roomRepository.save(room);
        stateEventRepository.save(new OnlineMatchStateEvent(
                roomId, room.getStateRevision(), senderId, stateJson));
        return snapshot(room);
    }

    private void validatePawnTransition(OnlineMatchRoom room, UUID senderId,
                                        UUID nextTurnOwnerId, Integer diceValue,
                                        int rollOpportunityId,
                                        boolean isDiceRolling, String stateJson) {
        try {
            JsonNode next = objectMapper.readTree(stateJson);
            JsonNode previous = room.getLatestStateJson() == null
                    ? null : objectMapper.readTree(room.getLatestStateJson());
            Map<String, Integer> before = pawnPositions(previous);
            Map<String, Integer> after = pawnPositions(next);
            int expectedPawns = room.getPlayerCount() * 4;
            if (after.size() != expectedPawns || (!before.isEmpty() && !before.keySet().equals(after.keySet()))) {
                throw invalidState();
            }
            if (next.path("isGameOver").asBoolean() && !hasFinishedPlayer(next)) {
                throw invalidState();
            }
            if (previous == null) {
                if (!room.getTurnOwnerId().equals(senderId)
                        || !senderId.equals(activePlayerId(next))
                        || !hasExpectedOnlineSeats(next, room)) throw invalidState();
                if (after.values().stream().anyMatch(step -> step != -1)) throw invalidState();
                return;
            }
            if (before.size() != expectedPawns) throw invalidState();

            List<String> changed = before.keySet().stream()
                    .filter(key -> !before.get(key).equals(after.get(key))).toList();
            if (changed.isEmpty()) {
                UUID nextActivePlayer = activePlayerId(next);
                if (nextActivePlayer == null || !nextActivePlayer.equals(nextTurnOwnerId)) {
                    throw invalidState();
                }
                if (nextTurnOwnerId.equals(senderId)) {
                    if (next.path("isGameOver").asBoolean()
                            && hasFinishedPlayer(next)) return;
                    if ("turnEnded".equals(next.path("turnPhase").asText())) {
                        if (diceValue == null || !room.matchesAuthoritativeRoll(
                                senderId, rollOpportunityId, diceValue)
                                || hasLegalMove(previous, senderId, diceValue)) {
                            throw invalidState();
                        }
                    }
                    return;
                }
                if (!nextTurnOwnerId.equals(nextActivePlayer(next, senderId))
                        || !"rollDice".equals(next.path("turnPhase").asText())) {
                    throw invalidState();
                }
                int transitionDice = diceValue != null ? diceValue
                        : previous == null ? Integer.MIN_VALUE
                        : previous.path("diceValue").asInt(Integer.MIN_VALUE);
                if (!room.hasAuthoritativeRoll(senderId, transitionDice)) {
                    throw invalidState();
                }
                boolean noMoveTurnEnd = previous != null
                        && "turnEnded".equals(previous.path("turnPhase").asText())
                        && !hasLegalMove(previous, senderId, transitionDice)
                        && previous.path("diceValue").asInt(Integer.MIN_VALUE) == transitionDice;
                boolean completedMoveTurnEnd = previous != null
                        && senderId.equals(activePlayerId(previous))
                        && "animating".equals(previous.path("turnPhase").asText())
                        && previous.path("lastMoveEvent").isObject()
                        && previous.path("diceValue").asInt(Integer.MIN_VALUE) == transitionDice
                        && !previous.path("lastCaptureEvent").isObject()
                        && ((transitionDice != 6
                                && previous.path("lastMoveEvent").path("toStep").asInt(-1) != 56)
                            || (previous.path("lastMoveEvent").path("toStep").asInt(-1) == 56
                                && hasPlayerFinishedPawns(previous, senderId)));
                if (!noMoveTurnEnd && !completedMoveTurnEnd) throw invalidState();
                return;
            }
            if (isDiceRolling) throw invalidState();
            if (changed.size() > 2 || diceValue == null || diceValue < 1 || diceValue > 6) {
                throw invalidState();
            }

            String movedPawn = changed.stream()
                    .filter(key -> key.startsWith(senderId + ":"))
                    .findFirst().orElseThrow(this::invalidState);
            if (changed.stream().filter(key -> key.startsWith(senderId + ":")).count() != 1) {
                throw invalidState();
            }
            int from = before.get(movedPawn);
            int to = after.get(movedPawn);
            int expected = from == -1 && diceValue == 6 ? 0
                    : from >= 0 && from <= 55 && from + diceValue <= 56
                            ? from + diceValue : Integer.MIN_VALUE;
            if (to != expected) throw invalidState();

            List<String> captured = changed.stream()
                    .filter(key -> !key.startsWith(senderId + ":")).toList();
            if (captured.size() > 1) throw invalidState();
            if (!captured.isEmpty()) {
                if (from < 0 || to > 50
                        || !isLegalCapture(previous, next, senderId, to, captured.getFirst())) {
                    throw invalidState();
                }
            } else if (from >= 0 && to <= 50 && hasCapturablePawn(previous, senderId, to)) {
                throw invalidState();
            }
            boolean playerFinished = hasPlayerFinishedPawns(next, senderId);
            boolean earnsExtraTurn = diceValue == 6 || !captured.isEmpty()
                    || (to == 56 && !playerFinished);
            UUID expectedTurnOwner = "animating".equals(next.path("turnPhase").asText())
                    || next.path("isGameOver").asBoolean() || earnsExtraTurn
                    ? senderId : nextActivePlayer(next, senderId);
            if (!room.getTurnOwnerId().equals(senderId)
                    || !nextTurnOwnerId.equals(expectedTurnOwner)) {
                throw invalidState();
            }
            if (next.path("isGameOver").asBoolean() && !hasFinishedPlayer(next)) {
                throw invalidState();
            }
        } catch (IllegalStateException exception) {
            throw exception;
        } catch (Exception exception) {
            throw invalidState();
        }
    }

    private UUID activePlayerId(JsonNode state) {
        JsonNode players = state.path("players");
        int currentIndex = state.path("currentTurnIndex").asInt(-1);
        if (!players.isArray() || currentIndex < 0 || currentIndex >= players.size()) return null;
        try {
            return UUID.fromString(players.get(currentIndex).path("id").asText());
        } catch (RuntimeException exception) {
            return null;
        }
    }

    private UUID nextActivePlayer(JsonNode state, UUID currentPlayerId) {
        JsonNode players = state.path("players");
        if (!players.isArray()) return null;
        int currentIndex = -1;
        for (int i = 0; i < players.size(); i++) {
            if (currentPlayerId.toString().equals(players.get(i).path("id").asText())) {
                currentIndex = i;
                break;
            }
        }
        if (currentIndex < 0) return null;
        for (int offset = 1; offset <= players.size(); offset++) {
            JsonNode player = players.get((currentIndex + offset) % players.size());
            try {
                UUID id = UUID.fromString(player.path("id").asText());
                if (!id.equals(currentPlayerId)
                        && !player.path("isEliminated").asBoolean()
                        && !hasPlayerFinishedPawns(player)) return id;
            } catch (RuntimeException ignored) { return null; }
        }
        return currentPlayerId;
    }

    private boolean hasExpectedOnlineSeats(JsonNode state, OnlineMatchRoom room) {
        JsonNode players = state.path("players");
        if (!players.isArray() || players.size() != room.getPlayerCount()) return false;
        Set<UUID> playerIds = new java.util.HashSet<>();
        Set<String> playerColors = new java.util.HashSet<>();
        for (JsonNode player : players) {
            try {
                UUID id = UUID.fromString(player.path("id").asText());
                String color = player.path("color").asText();
                if (!room.contains(id) || !room.getPlayers().stream()
                        .anyMatch(p -> p.id().equals(id) && p.color().equals(color))) return false;
                playerIds.add(id);
                playerColors.add(color);
            } catch (RuntimeException e) {
                return false;
            }
        }
        return playerIds.size() == room.getPlayerCount()
                && playerColors.size() == room.getPlayerCount();
    }

    private String playerIdForColor(JsonNode state, String color) {
        for (JsonNode player : state.path("players")) {
            if (color.equals(player.path("color").asText())) return player.path("id").asText();
        }
        return "";
    }

    private boolean hasFinishedPlayer(JsonNode state) {
        for (JsonNode player : state.path("players")) {
            if (hasPlayerFinishedPawns(player)) return true;
        }
        return false;
    }

    private boolean hasPlayerFinishedPawns(JsonNode state, UUID playerId) {
        for (JsonNode player : state.path("players")) {
            if (playerId.toString().equals(player.path("id").asText())) {
                return hasPlayerFinishedPawns(player);
            }
        }
        return false;
    }

    private boolean hasPlayerFinishedPawns(JsonNode player) {
        JsonNode pawns = player.path("pawns");
        if (!pawns.isArray() || pawns.size() != 4) return false;
        for (JsonNode pawn : pawns) {
            if (pawn.path("stepCount").asInt(-1) != 56) return false;
        }
        return true;
    }

    private boolean hasLegalMove(JsonNode state, UUID playerId, int diceValue) {
        if (diceValue < 1 || diceValue > 6) return false;
        for (JsonNode player : state.path("players")) {
            if (!playerId.toString().equals(player.path("id").asText())) continue;
            for (JsonNode pawn : player.path("pawns")) {
                int step = pawn.path("stepCount").asInt(-1);
                if (step == -1 && diceValue == 6) return true;
                if (step >= 0 && step <= 55 && step + diceValue <= 56) return true;
            }
            return false;
        }
        return false;
    }

    private Map<String, Integer> pawnPositions(JsonNode state) {
        Map<String, Integer> positions = new LinkedHashMap<>();
        if (state == null || !state.path("players").isArray()) return positions;
        for (JsonNode player : state.path("players")) {
            String playerId = player.path("id").asText("");
            String color = player.path("color").asText("");
            JsonNode pawns = player.path("pawns");
            if (playerId.isBlank()
                    || !Set.of("red", "green", "yellow", "blue").contains(color)
                    || !pawns.isArray() || pawns.size() != 4) {
                return Map.of();
            }
            for (JsonNode pawn : pawns) {
                int pawnId = pawn.path("id").asInt(-1);
                int step = pawn.path("stepCount").asInt(Integer.MIN_VALUE);
                if (pawnId < 0 || pawnId > 3 || step < -1 || step > 56) return Map.of();
                positions.put(playerId + ":" + color + ":" + pawnId, step);
            }
        }
        return positions;
    }

    private boolean isLegalCapture(JsonNode previous, JsonNode next, UUID moverId, int targetStep,
                                   String capturedKey) {
        String[] parts = capturedKey.split(":");
        if (parts.length != 3 || parts[0].equals(moverId.toString())) return false;
        String color = colorForPlayer(previous, moverId);
        String opponentColor = parts[1];
        int target = globalTile(color, targetStep);
        int previousStep = pawnPositions(previous).getOrDefault(capturedKey, -1);
        int nextStep = pawnPositions(next).getOrDefault(capturedKey, Integer.MIN_VALUE);
        return target >= 0 && !isSafeTile(target)
                && previousStep >= 0 && previousStep <= 50 && nextStep == -1
                && globalTile(opponentColor, previousStep) == target
                && countOpponentPawnsOnTile(previous, moverId, target) == 1;
    }

    private boolean hasCapturablePawn(JsonNode state, UUID moverId, int targetStep) {
        int target = globalTile(colorForPlayer(state, moverId), targetStep);
        return target >= 0 && !isSafeTile(target)
                && countOpponentPawnsOnTile(state, moverId, target) == 1;
    }

    private int countOpponentPawnsOnTile(JsonNode state, UUID moverId, int target) {
        int count = 0;
        for (JsonNode player : state.path("players")) {
            if (moverId.toString().equals(player.path("id").asText())) continue;
            String color = player.path("color").asText();
            for (JsonNode pawn : player.path("pawns")) {
                int step = pawn.path("stepCount").asInt(-1);
                if (step >= 0 && step <= 50 && globalTile(color, step) == target) count++;
            }
        }
        return count;
    }

    private String colorForPlayer(JsonNode state, UUID playerId) {
        for (JsonNode player : state.path("players")) {
            if (playerId.toString().equals(player.path("id").asText())) {
                return player.path("color").asText("");
            }
        }
        return "";
    }

    private int globalTile(String color, int step) {
        if (step < 0 || step > 50) return -1;
        int entry = switch (color) {
            case "red" -> 1;
            case "green" -> 14;
            case "yellow" -> 27;
            case "blue" -> 40;
            default -> -100;
        };
        return entry < 0 ? -1 : (entry + step) % 52;
    }

    private boolean isSafeTile(int tile) {
        return Set.of(1, 14, 27, 40, 9, 22, 35, 48).contains(tile);
    }

    private IllegalStateException invalidState() {
        return new IllegalStateException("The submitted board transition is invalid.");
    }

    @Transactional
    public int issueDiceRoll(String roomId, UUID playerId, int rollOpportunityId) {
        if (rollOpportunityId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A valid roll opportunity is required.");
        }
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Match room not found."));
        try {
            int diceValue = diceRandom.nextInt(6) + 1;
            int result = room.issueDiceRoll(playerId, rollOpportunityId, diceValue);
            roomRepository.save(room);
            return result;
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @Transactional(readOnly = true)
    public List<RoomSnapshot> getActiveRoomsForPlayer(UUID playerId) {
        return roomRepository.findActiveForPlayer(playerId, ACTIVE_STATUSES).stream()
                .map(MatchmakingService::snapshot).toList();
    }

    @Transactional
    public void touchPlayer(String roomId, UUID playerId) {
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId).orElse(null);
        if (room == null || !room.contains(playerId)
                || !ACTIVE_STATUSES.contains(room.getStatus())) return;
        room.touch();
        roomRepository.save(room);
    }

    private OnlineMatchRoom findActiveRoom(UUID playerId) {
        List<OnlineMatchRoom> rooms = roomRepository.findActiveForPlayer(playerId, ACTIVE_STATUSES);
        return rooms.isEmpty() ? null : rooms.getFirst();
    }

    private Map<UUID, PlayerWallet> lockWallets(List<UUID> requestedPlayerIds) {
        List<UUID> playerIds = new ArrayList<>(requestedPlayerIds);
        playerIds.sort(Comparator.comparing(UUID::toString));
        Map<UUID, PlayerWallet> wallets = new LinkedHashMap<>();
        for (UUID playerId : playerIds) {
            PlayerWallet wallet = walletRepository.findByPlayerIdForUpdate(playerId)
                    .orElseGet(() -> walletRepository.saveAndFlush(new PlayerWallet(playerId, 2000L)));
            wallets.put(playerId, wallet);
        }
        return wallets;
    }

    private void deductEntryFee(PlayerWallet wallet, long entryFee, String roomId) {
        long before = wallet.getBalance();
        long after = before - entryFee;
        wallet.setBalance(after);
        walletRepository.save(wallet);
        transactionRepository.save(new GoldTransaction(
                wallet.getPlayerId(), GoldTransaction.TransactionType.SPEND,
                entryFee, before, after, roomId, "MATCHMAKING_ENTRY_FEE"));
    }

    private void refundRoom(OnlineMatchRoom room) {
        Map<UUID, PlayerWallet> wallets = lockWallets(room.getPlayerIds());
        for (PlayerWallet wallet : wallets.values()) {
            long before = wallet.getBalance();
            long after = before + room.getEntryFee();
            wallet.setBalance(after);
            walletRepository.save(wallet);
            transactionRepository.save(new GoldTransaction(
                    wallet.getPlayerId(), GoldTransaction.TransactionType.REFUND,
                    room.getEntryFee(), before, after,
                    room.getRoomId(), "MATCHMAKING_CANCELLED"));
        }
    }

    private void cancelOrFinish(OnlineMatchRoom room) {
        if (room.getStatus() == OnlineMatchRoom.Status.MATCHED) {
            refundRoom(room);
            room.cancel();
        } else {
            room.finish();
        }
        roomRepository.save(room);
    }

    private static MatchmakingResponseDto responseFor(OnlineMatchRoom room, UUID playerId) {
        UUID opponentId = room.opponentOf(playerId);
        if (opponentId == null) return searchingResponse();
        MatchmakingResponseDto response = new MatchmakingResponseDto(
                true, room.getRoomId(), opponentId,
                room.nameOf(opponentId), room.avatarOf(opponentId),
                room.countryOf(opponentId), room.flagOf(opponentId), "Match Found!");
        response.setPlayerId(playerId);
        response.setPlayerCount(room.getPlayerCount());
        response.setPlayers(room.getPlayers().stream().map(player ->
                new MatchmakingResponseDto.MatchPlayerDto(player.id(), player.name(),
                        player.avatarUrl(), player.country(), player.countryFlag(),
                        player.color())).toList());
        return response;
    }

    private static RoomSnapshot snapshot(OnlineMatchRoom room) {
        return new RoomSnapshot(room.getRoomId(), room.getStatus(),
                room.getPlayerIds(), room.getPlayerIds().stream().filter(room::isConnected).toList(),
                room.getTurnOwnerId(), room.getStateRevision(),
                room.getLatestStateSenderId(), room.getLatestStateJson());
    }

    private static MatchmakingResponseDto searchingResponse() {
        return new MatchmakingResponseDto(false, null, null, null, null, null, null,
                "Searching for online players...");
    }

    private static MatchmakingResponseDto insufficientFunds() {
        return new MatchmakingResponseDto(false, null, null, null, null, null, null,
                "Insufficient gold coins for entry fee.");
    }

    private static String nonBlank(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
