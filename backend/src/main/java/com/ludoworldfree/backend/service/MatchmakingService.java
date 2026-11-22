package com.ludoworldfree.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.ludoworldfree.backend.dto.MatchmakingRequestDto;
import com.ludoworldfree.backend.dto.MatchmakingResponseDto;
import com.ludoworldfree.backend.dto.FriendPlayRoomSeatDto;
import com.ludoworldfree.backend.model.GoldTransaction;
import com.ludoworldfree.backend.model.MatchmakingTicket;
import com.ludoworldfree.backend.model.OnlineMatchRoom;
import com.ludoworldfree.backend.model.OnlineMatchStateEvent;
import com.ludoworldfree.backend.model.PlayerProfile;
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
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.locks.ReentrantLock;
import java.security.SecureRandom;
import java.time.Instant;

@Service
public class MatchmakingService {
    private static final Logger log = LoggerFactory.getLogger(MatchmakingService.class);
    private static final List<OnlineMatchRoom.Status> ACTIVE_STATUSES =
            List.of(OnlineMatchRoom.Status.MATCHED, OnlineMatchRoom.Status.READY);
    private static final long MATCHMAKING_TICKET_TTL_SECONDS = 60;
    private static final Set<Long> ALLOWED_ENTRY_FEES = Set.of(
            250L, 500L, 1_000L, 2_000L, 4_000L, 8_000L,
            16_000L, 25_000L, 50_000L, 100_000L);

    public record RoomSnapshot(
            String roomId,
            OnlineMatchRoom.Status status,
            List<UUID> playerIds,
            List<UUID> connectedPlayerIds,
            UUID turnOwnerId,
            long stateRevision,
            UUID latestStateSenderId,
            String latestStateJson,
            long rematchRevision,
            UUID rematchRoundId,
            UUID rematchRequesterId,
            OnlineMatchRoom.RematchStatus rematchStatus,
            List<UUID> rematchAcceptedPlayerIds) {
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
    private final JdbcTemplate jdbc;
    private final boolean postgresDatabase;
    private final ConcurrentMap<String, ReentrantLock> localQueueLocks = new ConcurrentHashMap<>();
    private final SecureRandom diceRandom = new SecureRandom();

    public MatchmakingService(MatchmakingTicketRepository ticketRepository,
                              OnlineMatchRoomRepository roomRepository,
                              OnlineMatchStateEventRepository stateEventRepository,
                              PlayerWalletRepository walletRepository,
                              GoldTransactionRepository transactionRepository,
                              ObjectMapper objectMapper,
                              JdbcTemplate jdbc) {
        this.ticketRepository = ticketRepository;
        this.roomRepository = roomRepository;
        this.stateEventRepository = stateEventRepository;
        this.walletRepository = walletRepository;
        this.transactionRepository = transactionRepository;
        this.objectMapper = objectMapper;
        this.jdbc = jdbc;
        this.postgresDatabase = Boolean.TRUE.equals(jdbc.execute(
                (ConnectionCallback<Boolean>) connection -> connection.getMetaData()
                        .getDatabaseProductName().toLowerCase().contains("postgres")));
    }

    @Transactional
    public MatchmakingResponseDto joinQueue(MatchmakingRequestDto request) {
        UUID playerId = request.getPlayerId();
        if (playerId == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "A player ID is required.");
        }
        if (!ALLOWED_ENTRY_FEES.contains(request.getEntryFee())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a supported online entry amount.");
        }
        if (request.getPlayerCount() != 2 && request.getPlayerCount() != 4) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Choose two or four players.");
        }
        String sessionId = request.getSessionId() == null
                ? "" : request.getSessionId().strip();
        if (sessionId.isEmpty() || sessionId.length() > 64) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A valid matchmaking session is required.");
        }
        Instant activeAfter = Instant.now().minusSeconds(MATCHMAKING_TICKET_TTL_SECONDS);
        ticketRepository.deleteByLastSeenAtBefore(activeAfter);
        List<String> colors = List.of("red", "green", "yellow", "blue");
        String selectedColor = request.getSelectedColor() == null
                ? "red" : request.getSelectedColor().toLowerCase();
        if (!colors.contains(selectedColor)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Choose a valid player color.");
        }
        String gameMode = request.getGameMode() == null
                ? "CLASSIC" : request.getGameMode().strip().toUpperCase();
        if (!Set.of("CLASSIC", "FIRST_KILL").contains(gameMode)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Choose a valid online game mode.");
        }
        acquireQueueLaneLock(request.getPlayerCount(), request.getEntryFee(), gameMode);

        OnlineMatchRoom activeRoom = null;
        List<OnlineMatchRoom> playerRooms = roomRepository.findActiveForPlayerForUpdate(
                playerId, ACTIVE_STATUSES);
        for (OnlineMatchRoom room : playerRooms) {
            boolean sameSessionAndMode = room.getPlayerCount() == request.getPlayerCount()
                    && gameMode.equals(room.getGameMode())
                    && sessionId.equals(room.sessionIdOf(playerId));
            if (sameSessionAndMode && activeRoom == null) {
                activeRoom = room;
            } else {
                cancelOrFinish(room);
            }
        }
        if (activeRoom != null) {
            deleteTicketForSession(playerId, sessionId);
            return responseFor(activeRoom, playerId);
        }

        var existingTicket = ticketRepository.findByPlayerIdForUpdate(playerId);
        MatchmakingTicket currentTicket;
        if (existingTicket.isPresent()
                && existingTicket.get().getEntryFee() == request.getEntryFee()
                && existingTicket.get().getPlayerCount() == request.getPlayerCount()
                && existingTicket.get().getGameMode().equals(gameMode)
                && sessionId.equals(existingTicket.get().getSessionId())
                && existingTicket.get().getSelectedColor().equals(selectedColor)) {
            currentTicket = existingTicket.get();
            ticketRepository.touchByPlayerId(playerId, Instant.now());
        } else {
            existingTicket.ifPresent(ticketRepository::delete);
            currentTicket = new MatchmakingTicket(
                    playerId,
                    nonBlank(request.getDisplayName(), "Player"),
                    request.getAvatarUrl(),
                    nonBlank(request.getCountry(), "World"),
                    nonBlank(request.getCountryFlag(), "🌐"),
                    request.getEntryFee(), request.getPlayerCount(), selectedColor,
                    sessionId, gameMode);
        }

        List<MatchmakingTicket> candidates = postgresDatabase
                ? ticketRepository.findWaitingCandidateForUpdate(
                        request.getEntryFee(), request.getPlayerCount(), gameMode, activeAfter,
                        playerId, OnlineMatchRoom.Status.MATCHED.name(),
                        OnlineMatchRoom.Status.READY.name(), request.getPlayerCount() - 1)
                : ticketRepository.findWaitingCandidatePortable(
                        request.getEntryFee(), request.getPlayerCount(), gameMode, activeAfter,
                        playerId, ACTIVE_STATUSES,
                        PageRequest.of(0, request.getPlayerCount() - 1));
        List<MatchmakingTicket> matchedTickets = selectCompatibleTickets(
                currentTicket, candidates, activeAfter);
        if (matchedTickets.isEmpty()) {
            PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                    .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));
            if (wallet.getBalance() < request.getEntryFee()) return insufficientFunds();
            ticketRepository.save(currentTicket);
            return lowerStakeOffer(currentTicket, activeAfter);
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
        ticketRepository.deleteById(playerId);
        ticketRepository.deleteAll(matchedTickets);
        log.info("Online match {} created for {} players", roomId, allTickets.size());
        return responseFor(room, playerId);
    }

    private MatchmakingResponseDto requeueCurrentTicket(MatchmakingTicket ticket) {
        ticketRepository.save(ticket);
        return searchingResponse(ticket.getGameMode(), ticket.getPlayerCount());
    }

    private MatchmakingResponseDto lowerStakeOffer(
            MatchmakingTicket current, Instant activeAfter) {
        List<MatchmakingTicket> lowerStakeCandidates =
                ticketRepository.findLowerStakeCandidatesForUpdate(
                        current.getEntryFee(), current.getPlayerCount(), current.getGameMode(), activeAfter,
                        current.getPlayerId(), ACTIVE_STATUSES,
                        PageRequest.of(0, current.getPlayerCount() - 1));
        Map<Long, Integer> candidatesByFee = new LinkedHashMap<>();
        for (MatchmakingTicket candidate : lowerStakeCandidates) {
            int count = candidatesByFee.merge(candidate.getEntryFee(), 1, Integer::sum);
            if (count >= current.getPlayerCount() - 1) {
                MatchmakingResponseDto response = searchingResponse(
                        current.getGameMode(), current.getPlayerCount());
                response.setLowerEntryFee(candidate.getEntryFee());
                response.setMessage("Players are available at a lower entry amount.");
                return response;
            }
        }
        return searchingResponse(current.getGameMode(), current.getPlayerCount());
    }

    private List<MatchmakingTicket> selectCompatibleTickets(
            MatchmakingTicket current, List<MatchmakingTicket> candidates,
            Instant activeAfter) {
        List<MatchmakingTicket> selected = new ArrayList<>();
        int needed = current.getPlayerCount() - 1;
        for (MatchmakingTicket candidate : candidates) {
            if (candidate.getPlayerCount() != current.getPlayerCount()
                    || !candidate.getGameMode().equals(current.getGameMode())
                    || candidate.getSessionId() == null
                    || candidate.getLastSeenAt().isBefore(activeAfter)
                    || candidate.getPlayerId().equals(current.getPlayerId())) {
                continue;
            }
            selected.add(candidate);
            if (selected.size() == needed) return selected;
        }
        return List.of();
    }

    @Transactional
    public MatchmakingResponseDto checkStatus(UUID playerId, int playerCount,
                                              String sessionId) {
        if (playerCount != 2 && playerCount != 4) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Choose two or four players.");
        }
        if (sessionId == null || sessionId.isBlank() || sessionId.length() > 64) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A valid matchmaking session is required.");
        }
        // Read without taking a row lock here: joinQueue acquires the lane lock
        // before room/ticket locks. This consistent order prevents simultaneous
        // status polls from deadlocking each other while matching.
        MatchmakingTicket ticket = ticketRepository.findById(playerId).orElse(null);
        if (ticket != null && sessionId.equals(ticket.getSessionId())
                && ticket.getPlayerCount() == playerCount) {
            MatchmakingRequestDto retry = new MatchmakingRequestDto(
                    playerId, ticket.getDisplayName(), ticket.getAvatarUrl(),
                    ticket.getCountry(), ticket.getCountryFlag(), ticket.getEntryFee());
            retry.setPlayerCount(ticket.getPlayerCount());
            retry.setSelectedColor(ticket.getSelectedColor());
            retry.setGameMode(ticket.getGameMode());
            retry.setSessionId(sessionId);
            return joinQueue(retry);
        }
        OnlineMatchRoom activeRoom = findActiveRoom(playerId, playerCount, sessionId);
        if (activeRoom != null) {
            deleteTicketForSession(playerId, sessionId);
            return responseFor(activeRoom, playerId);
        }
        return searchingResponse();
    }

    private void acquireQueueLaneLock(int playerCount, long entryFee, String gameMode) {
        String laneKey = playerCount + ":" + entryFee + ":" + gameMode;
        if (postgresDatabase) {
            jdbc.execute("SELECT pg_advisory_xact_lock(hashtext(?), 0)",
                    (PreparedStatementCallback<Void>) statement -> {
                        statement.setString(1, laneKey);
                        statement.execute();
                        return null;
                    });
            return;
        }

        ReentrantLock lock = localQueueLocks.computeIfAbsent(laneKey,
                ignored -> new ReentrantLock());
        lock.lock();
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCompletion(int status) {
                    lock.unlock();
                }
            });
        } else {
            lock.unlock();
        }
    }

    @Transactional
    public MatchmakingResponseDto createBuddyRoom(
            UUID requesterId, PlayerProfile requester, String requesterSessionId,
            String requesterColor, UUID targetId, PlayerProfile target,
            String targetSessionId, long entryFee, String gameMode) {
        if (!ALLOWED_ENTRY_FEES.contains(entryFee)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a supported online entry amount.");
        }
        if (!Set.of("CLASSIC", "FIRST_KILL").contains(gameMode)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a valid online game mode.");
        }
        if (requesterSessionId == null || requesterSessionId.isBlank()
                || requesterSessionId.length() > 64
                || targetSessionId == null || targetSessionId.isBlank()
                || targetSessionId.length() > 64) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A valid game session is required.");
        }
        List<String> colors = List.of("red", "green", "yellow", "blue");
        String color = requesterColor == null ? "red" : requesterColor.toLowerCase();
        if (!colors.contains(color)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a valid player color.");
        }
        List<OnlineMatchRoom> existingRooms = new ArrayList<>();
        existingRooms.addAll(roomRepository.findActiveForPlayerForUpdate(
                requesterId, ACTIVE_STATUSES));
        existingRooms.addAll(roomRepository.findActiveForPlayerForUpdate(
                targetId, ACTIVE_STATUSES));
        Instant now = Instant.now();
        Set<String> processedRoomIds = new HashSet<>();
        for (OnlineMatchRoom existingRoom : existingRooms) {
            if (!processedRoomIds.add(existingRoom.getRoomId())) continue;
            if (existingRoom.getLatestStateJson() == null) {
                refundRoom(existingRoom);
                existingRoom.cancel();
                roomRepository.save(existingRoom);
            } else if (existingRoom.isAbandoned(now)) {
                cancelOrFinish(existingRoom);
            } else {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "One of these players is already in an online game.");
            }
        }

        MatchmakingTicket requesterTicket = new MatchmakingTicket(
                requesterId, requester.getDisplayName(), requester.getAvatarUrl(),
                requester.getCountry(), requester.getCountryFlag(), entryFee, 2,
                color, requesterSessionId, gameMode);
        String targetColor = switch (color) {
            case "red" -> "yellow";
            case "green" -> "blue";
            case "yellow" -> "red";
            default -> "green";
        };
        MatchmakingTicket targetTicket = new MatchmakingTicket(
                targetId, target.getDisplayName(), target.getAvatarUrl(),
                target.getCountry(), target.getCountryFlag(), entryFee, 2,
                targetColor, targetSessionId, gameMode);

        MatchmakingTicket requesterQueueTicket = ticketRepository
                .findByPlayerIdForUpdate(requesterId).orElse(null);
        MatchmakingTicket targetQueueTicket = ticketRepository
                .findByPlayerIdForUpdate(targetId).orElse(null);
        Map<UUID, PlayerWallet> wallets = lockWallets(List.of(requesterId, targetId));
        if (wallets.get(requesterId).getBalance() < entryFee
                || wallets.get(targetId).getBalance() < entryFee) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Both buddies need enough coins for this entry amount.");
        }

        if (requesterQueueTicket != null) ticketRepository.delete(requesterQueueTicket);
        if (targetQueueTicket != null) ticketRepository.delete(targetQueueTicket);

        String roomId = UUID.randomUUID().toString();
        deductEntryFee(wallets.get(requesterId), entryFee, roomId);
        deductEntryFee(wallets.get(targetId), entryFee, roomId);
        transactionRepository.flush();

        OnlineMatchRoom room = new OnlineMatchRoom(
                roomId, List.of(requesterTicket, targetTicket), entryFee);
        roomRepository.saveAndFlush(room);
        return responseFor(room, requesterId);
    }

    @Transactional(readOnly = true)
    public MatchmakingResponseDto responseForBuddyRoom(String roomId, UUID playerId) {
        return roomRepository.findById(roomId)
                .filter(room -> ACTIVE_STATUSES.contains(room.getStatus())
                        && room.contains(playerId))
                .map(room -> responseFor(room, playerId))
                .orElse(null);
    }

    @Transactional
    public MatchmakingResponseDto createFriendPlayRoomMatch(
            String roomId, long entryFee, String gameMode,
            List<FriendPlayRoomSeatDto> seats) {
        if (seats == null || (seats.size() != 2 && seats.size() != 4)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "The room needs two or four players before the game can start.");
        }
        if (entryFee < 0 || gameMode == null
                || !Set.of("CLASSIC", "FIRST_KILL").contains(gameMode)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "The friend room settings are invalid.");
        }
        Set<UUID> playerIds = new HashSet<>();
        Set<String> colors = new HashSet<>();
        List<MatchmakingTicket> tickets = new ArrayList<>();
        for (FriendPlayRoomSeatDto seat : seats) {
            String color = seat.selectedColor() == null
                    ? "" : seat.selectedColor().toLowerCase();
            if (seat.playerId() == null || !playerIds.add(seat.playerId())
                    || !List.of("red", "green", "yellow", "blue").contains(color)
                    || !colors.add(color)
                    || seat.sessionId() == null || seat.sessionId().isBlank()) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "Player seats or colors in this room are invalid.");
            }
            if (isPlayerInActiveRoom(seat.playerId())) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "A player is already in an online game.");
            }
            tickets.add(new MatchmakingTicket(seat.playerId(),
                    nonBlank(seat.displayName(), "Player"), seat.avatarUrl(),
                    nonBlank(seat.country(), "World"), nonBlank(seat.countryFlag(), "🌐"),
                    entryFee, seats.size(), color, seat.sessionId(), gameMode));
        }

        Map<UUID, PlayerWallet> wallets = lockWallets(new ArrayList<>(playerIds));
        for (PlayerWallet wallet : wallets.values()) {
            if (wallet.getBalance() < entryFee) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "Every player needs enough coins for the entry amount.");
            }
        }
        for (PlayerWallet wallet : wallets.values()) deductEntryFee(wallet, entryFee, roomId);
        transactionRepository.flush();

        OnlineMatchRoom room = new OnlineMatchRoom(roomId, tickets, entryFee);
        roomRepository.saveAndFlush(room);
        return responseFor(room, tickets.getFirst().getPlayerId());
    }

    @Transactional(readOnly = true)
    public boolean isPlayerInRoom(UUID playerId, String roomId) {
        if (playerId == null || roomId == null) return false;
        return roomRepository.findById(roomId)
                .filter(room -> ACTIVE_STATUSES.contains(room.getStatus()) && room.contains(playerId))
                .isPresent();
    }

    @Transactional(readOnly = true)
    public boolean isPlayerInActiveRoom(UUID playerId) {
        Instant now = Instant.now();
        return roomRepository.findActiveForPlayer(playerId, ACTIVE_STATUSES).stream()
                .anyMatch(room -> room.getLatestStateJson() != null
                        && !room.isAbandoned(now));
    }

    @Transactional
    public void leaveActiveRoomsForBuddyGame(UUID requesterId, UUID targetId) {
        Map<UUID, List<OnlineMatchRoom>> roomsByPlayer = new LinkedHashMap<>();
        roomsByPlayer.put(requesterId,
                roomRepository.findActiveForPlayerForUpdate(requesterId, ACTIVE_STATUSES));
        if (!requesterId.equals(targetId)) {
            roomsByPlayer.put(targetId,
                    roomRepository.findActiveForPlayerForUpdate(targetId, ACTIVE_STATUSES));
        }
        Set<String> processedRoomIds = new HashSet<>();
        for (Map.Entry<UUID, List<OnlineMatchRoom>> entry : roomsByPlayer.entrySet()) {
            UUID leavingPlayerId = entry.getKey();
            for (OnlineMatchRoom room : entry.getValue()) {
                if (!processedRoomIds.add(room.getRoomId())) continue;
                if (room.getLatestStateJson() == null
                        || room.getStatus() == OnlineMatchRoom.Status.MATCHED) {
                    refundRoom(room);
                    room.cancel();
                    roomRepository.save(room);
                } else {
                    forfeitPlayerLeaving(room.getRoomId(), leavingPlayerId);
                }
            }
        }
    }

    @Transactional(readOnly = true)
    public boolean isPlayerInRoom(UUID playerId, String roomId, String sessionId) {
        if (playerId == null || roomId == null || sessionId == null || sessionId.isBlank()) {
            return false;
        }
        return roomRepository.findById(roomId)
                .filter(room -> ACTIVE_STATUSES.contains(room.getStatus())
                        && room.contains(playerId)
                        && sessionId.equals(room.sessionIdOf(playerId)))
                .isPresent();
    }

    @Transactional
    public void cancelQueue(UUID playerId, String sessionId) {
        MatchmakingTicket ticket = ticketRepository.findByPlayerIdForUpdate(playerId)
                .orElse(null);
        if (ticket != null && (sessionId == null || sessionId.isBlank()
                || sessionId.equals(ticket.getSessionId()))) {
            ticketRepository.delete(ticket);
        }
        List<OnlineMatchRoom> rooms = roomRepository.findActiveForPlayerForUpdate(
                playerId, ACTIVE_STATUSES);
        for (OnlineMatchRoom room : rooms) {
            if (sessionId == null || sessionId.isBlank()
                    || sessionId.equals(room.sessionIdOf(playerId))) {
                cancelOrFinish(room);
            }
        }
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

    @Transactional
    public RoomSnapshot forfeitDisconnectedPlayer(String roomId, UUID requesterId,
                                                   UUID disconnectedPlayerId) {
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Match room not found."));
        if (room.getStatus() != OnlineMatchRoom.Status.READY
                || room.getPlayerCount() != 2
                || requesterId.equals(disconnectedPlayerId)
                || !room.isConnected(requesterId)
                || room.isConnected(disconnectedPlayerId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "This player cannot forfeit the disconnected opponent.");
        }
        if (room.getLatestStateJson() == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "The online game has not started yet.");
        }

        try {
            JsonNode parsed = objectMapper.readTree(room.getLatestStateJson());
            if (!(parsed instanceof ObjectNode next)) {
                throw new IllegalStateException("Invalid stored game state.");
            }
            ArrayNode players = (ArrayNode) next.path("players");
            int disconnectedIndex = -1;
            int winnerIndex = -1;
            int eliminationOrder = 1;
            for (int index = 0; index < players.size(); index++) {
                JsonNode player = players.get(index);
                UUID id = UUID.fromString(player.path("id").asText());
                if (player.path("isEliminated").asBoolean()) eliminationOrder++;
                if (id.equals(disconnectedPlayerId)) disconnectedIndex = index;
                if (id.equals(requesterId)) winnerIndex = index;
            }
            if (players.size() != 2 || disconnectedIndex < 0 || winnerIndex < 0) {
                throw new IllegalStateException("Stored players do not match the room.");
            }
            if (next.path("isGameOver").asBoolean()) return snapshot(room);

            ObjectNode disconnected = (ObjectNode) players.get(disconnectedIndex);
            ObjectNode winner = (ObjectNode) players.get(winnerIndex);
            disconnected.put("isEliminated", true);
            disconnected.put("eliminationOrder", eliminationOrder);
            disconnected.put("rank", 2);
            winner.put("rank", 1);
            next.put("currentTurnIndex", winnerIndex);
            next.put("turnPhase", "turnEnded");
            next.put("isDiceRolling", false);
            next.put("turnTimerPaused", false);
            next.put("turnTimerRemainingMilliseconds", 0);
            next.put("isGameOver", true);
            next.put("statusMessage", winner.path("name").asText("Opponent")
                    + " wins by forfeit!");
            ArrayNode winnerIds = next.withArray("winnerIds");
            boolean winnerAlreadyRecorded = false;
            for (JsonNode winnerId : winnerIds) {
                if (requesterId.toString().equals(winnerId.asText())) {
                    winnerAlreadyRecorded = true;
                    break;
                }
            }
            if (!winnerAlreadyRecorded) winnerIds.add(requesterId.toString());

            String stateJson = objectMapper.writeValueAsString(next);
            room.recordState(disconnectedPlayerId, requesterId, stateJson);
            settleOnlineWinner(room, stateJson);
            roomRepository.save(room);
            stateEventRepository.save(new OnlineMatchStateEvent(
                    roomId, room.getStateRevision(), disconnectedPlayerId, stateJson));
            return snapshot(room);
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "The disconnected player could not be forfeited.", exception);
        }
    }

    @Transactional
    public RoomSnapshot forfeitPlayerLeaving(String roomId, UUID leavingPlayerId) {
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId).orElse(null);
        if (room == null || !room.contains(leavingPlayerId)
                || room.getStatus() == OnlineMatchRoom.Status.FINISHED
                || room.getStatus() == OnlineMatchRoom.Status.CANCELLED) {
            return room == null ? null : snapshot(room);
        }
        if (room.getStatus() == OnlineMatchRoom.Status.MATCHED) {
            refundRoom(room);
            room.cancel();
            return snapshot(roomRepository.save(room));
        }

        if (room.getPlayerCount() == 2 && room.getLatestStateJson() != null) {
            try {
                JsonNode latest = objectMapper.readTree(room.getLatestStateJson());
                String stateJson = room.getLatestStateJson();
                if (!latest.path("isGameOver").asBoolean()) {
                    UUID winnerId = room.getPlayerIds().stream()
                            .filter(id -> !id.equals(leavingPlayerId))
                            .findFirst().orElseThrow();
                    stateJson = createForfeitState(
                            latest, leavingPlayerId, winnerId);
                    room.recordState(leavingPlayerId, winnerId, stateJson);
                    stateEventRepository.save(new OnlineMatchStateEvent(
                            roomId, room.getStateRevision(), leavingPlayerId, stateJson));
                }
                settleOnlineWinner(room, stateJson);
            } catch (Exception exception) {
                log.warn("Could not record forfeit for player {} in room {}: {}",
                        leavingPlayerId, roomId, exception.getMessage());
            }
        }

        room.finish();
        return snapshot(roomRepository.save(room));
    }

    private String createForfeitState(JsonNode latest, UUID forfeitingPlayerId,
                                      UUID winnerId) throws Exception {
        if (!(latest.deepCopy() instanceof ObjectNode next)) {
            throw new IllegalStateException("Invalid stored game state.");
        }
        ArrayNode players = (ArrayNode) next.path("players");
        int forfeitingIndex = -1;
        int winnerIndex = -1;
        int eliminationOrder = 1;
        for (int index = 0; index < players.size(); index++) {
            JsonNode player = players.get(index);
            UUID id = UUID.fromString(player.path("id").asText());
            if (player.path("isEliminated").asBoolean()) eliminationOrder++;
            if (id.equals(forfeitingPlayerId)) forfeitingIndex = index;
            if (id.equals(winnerId)) winnerIndex = index;
        }
        if (players.size() != 2 || forfeitingIndex < 0 || winnerIndex < 0) {
            throw new IllegalStateException("Stored players do not match the room.");
        }

        ObjectNode forfeitingPlayer = (ObjectNode) players.get(forfeitingIndex);
        ObjectNode winner = (ObjectNode) players.get(winnerIndex);
        forfeitingPlayer.put("isEliminated", true);
        forfeitingPlayer.put("eliminationOrder", eliminationOrder);
        forfeitingPlayer.put("rank", 2);
        winner.put("rank", 1);
        next.put("currentTurnIndex", winnerIndex);
        next.put("turnPhase", "turnEnded");
        next.put("isDiceRolling", false);
        next.put("turnTimerPaused", false);
        next.put("turnTimerRemainingMilliseconds", 0);
        next.put("isGameOver", true);
        next.put("statusMessage", winner.path("name").asText("Opponent")
                + " wins by forfeit!");
        ArrayNode winnerIds = next.withArray("winnerIds");
        boolean winnerAlreadyRecorded = false;
        for (JsonNode existingWinner : winnerIds) {
            if (winnerId.toString().equals(existingWinner.asText())) {
                winnerAlreadyRecorded = true;
                break;
            }
        }
        if (!winnerAlreadyRecorded) winnerIds.add(winnerId.toString());
        return objectMapper.writeValueAsString(next);
    }

    private void settleOnlineWinner(OnlineMatchRoom room, String stateJson) {
        if (room.getPlayerCount() != 2 || stateJson == null
                || transactionRepository.existsByReferenceIdAndSource(
                        room.getRoomId(), "ONLINE_MATCH_WIN")) {
            return;
        }
        try {
            JsonNode state = objectMapper.readTree(stateJson);
            if (!state.path("isGameOver").asBoolean()
                    || !state.path("winnerIds").isArray()
                    || state.path("winnerIds").isEmpty()) {
                return;
            }
            UUID winnerId = UUID.fromString(state.path("winnerIds").get(0).asText());
            if (!room.contains(winnerId)) return;
            long reward = Math.multiplyExact(room.getEntryFee(), 2L);
            if (reward <= 0) return;
            PlayerWallet winnerWallet = walletRepository.findByPlayerIdForUpdate(winnerId)
                    .orElseGet(() -> walletRepository.saveAndFlush(
                            new PlayerWallet(winnerId, 2000L)));
            long before = winnerWallet.getBalance();
            long after = Math.addExact(before, reward);
            winnerWallet.setBalance(after);
            walletRepository.save(winnerWallet);
            transactionRepository.save(new GoldTransaction(
                    winnerId, GoldTransaction.TransactionType.GAME_REWARD,
                    reward, before, after, room.getRoomId(), "ONLINE_MATCH_WIN"));
        } catch (Exception exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "The online match reward could not be credited.", exception);
        }
    }

    @Transactional(readOnly = true)
    public RoomSnapshot getRoomSnapshot(String roomId) {
        return roomRepository.findById(roomId).map(MatchmakingService::snapshot).orElse(null);
    }

    @Transactional(readOnly = true)
    public Map<String, RoomSnapshot> getRoomSnapshots(Collection<String> roomIds) {
        if (roomIds == null || roomIds.isEmpty()) return Map.of();
        return roomRepository.findAllByRoomIdIn(roomIds).stream()
                .collect(java.util.stream.Collectors.toMap(
                        OnlineMatchRoom::getRoomId, MatchmakingService::snapshot));
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
        boolean validForfeit = isValidOnlineForfeit(
                room, senderId, nextTurnOwnerId, stateJson);
        if (room.getStatus() != OnlineMatchRoom.Status.READY
                || !roomPlayerIds.equals(statePlayerIds)
                || (!senderId.equals(room.getTurnOwnerId()) && !validForfeit)
                || !roomPlayerIds.contains(nextTurnOwnerId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "This player cannot submit the current game state.");
        }
        if (!validForfeit && !isDiceRolling && diceValue != null
                && !room.matchesAuthoritativeRoll(senderId, rollOpportunityId, diceValue)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "The submitted dice result was not issued by the server.");
        }
        if (!validForfeit) {
            validatePawnTransition(room, senderId, nextTurnOwnerId, diceValue,
                    rollOpportunityId, isDiceRolling, stateJson);
        }
        room.recordState(senderId, nextTurnOwnerId, stateJson);
        settleOnlineWinner(room, stateJson);
        roomRepository.save(room);
        stateEventRepository.save(new OnlineMatchStateEvent(
                roomId, room.getStateRevision(), senderId, stateJson));
        return snapshot(room);
    }

    private boolean isValidOnlineForfeit(OnlineMatchRoom room, UUID senderId,
                                         UUID nextTurnOwnerId, String stateJson) {
        try {
            JsonNode next = objectMapper.readTree(stateJson);
            UUID activePlayerId = activePlayerId(next);
            if (!next.path("players").isArray()
                    || next.path("players").size() != room.getPlayerCount()
                    || senderId.equals(nextTurnOwnerId)
                    || !nextTurnOwnerId.equals(activePlayerId)) return false;
            JsonNode forfeitingPlayer = null;
            JsonNode winner = null;
            Set<UUID> stateIds = new java.util.HashSet<>();
            for (JsonNode player : next.path("players")) {
                UUID id = UUID.fromString(player.path("id").asText());
                stateIds.add(id);
                if (senderId.equals(id)) forfeitingPlayer = player;
                if (nextTurnOwnerId.equals(id)) winner = player;
            }
            if (!stateIds.equals(Set.copyOf(room.getPlayerIds()))
                    || forfeitingPlayer == null
                    || !forfeitingPlayer.path("isEliminated").asBoolean()) {
                return false;
            }
            if (next.path("isGameOver").asBoolean()) {
                boolean winnerRecorded = false;
                for (JsonNode winnerId : next.path("winnerIds")) {
                    if (nextTurnOwnerId.toString().equals(winnerId.asText())) {
                        winnerRecorded = true;
                        break;
                    }
                }
                if (winner == null || winner.path("rank").asInt(0) <= 0
                        || !winnerRecorded) return false;
            } else if (senderId.equals(nextTurnOwnerId)
                    || !"rollDice".equals(next.path("turnPhase").asText())) {
                return false;
            }
            if (room.getLatestStateJson() == null) return false;
            JsonNode previous = objectMapper.readTree(room.getLatestStateJson());
            Map<String, Integer> before = pawnPositions(previous);
            Map<String, Integer> after = pawnPositions(next);
            return before.size() == room.getPlayerCount() * 4
                    && before.equals(after);
        } catch (Exception exception) {
            return false;
        }
    }

    @Transactional
    public RoomSnapshot requestRematch(String roomId, UUID requesterId) {
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Match room not found."));
        if (room.getStatus() != OnlineMatchRoom.Status.READY || !room.contains(requesterId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "This player cannot request a replay.");
        }
        // The replay button is only exposed after the client reaches game over.
        // Do not gate the request on the last persisted board: its final update
        // can still be in flight when the player taps Replay.
        if (room.getRematchStatus() == OnlineMatchRoom.RematchStatus.REQUESTED) {
            if (!requesterId.equals(room.getRematchRequesterId())) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "A replay request is already pending.");
            }
            return snapshot(room);
        }
        room.requestRematch(requesterId);
        return snapshot(roomRepository.save(room));
    }

    @Transactional
    public RoomSnapshot respondToRematch(String roomId, UUID playerId, UUID roundId, boolean accept) {
        OnlineMatchRoom room = roomRepository.findForUpdate(roomId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Match room not found."));
        if (room.getStatus() != OnlineMatchRoom.Status.READY || !room.contains(playerId)
                || room.getRematchStatus() != OnlineMatchRoom.RematchStatus.REQUESTED
                || !room.getRematchRoundId().equals(roundId)
                || playerId.equals(room.getRematchRequesterId())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "This replay request is no longer active.");
        }
        if (!accept) {
            room.recordRematchDeclined();
            return snapshot(roomRepository.save(room));
        }
        List<UUID> accepted = new ArrayList<>(snapshot(room).rematchAcceptedPlayerIds());
        if (!accepted.contains(playerId)) accepted.add(playerId);
        if (accepted.size() == room.getPlayerCount()) {
            UUID firstPlayer = room.getPlayerIds().stream()
                    .min(Comparator.comparing(UUID::toString)).orElseThrow();
            room.recordRematchAccepted(accepted.stream().map(UUID::toString)
                    .collect(java.util.stream.Collectors.joining(",")));
            room.startAcceptedRematch(firstPlayer);
        } else {
            room.recordRematchAccepted(accepted.stream().map(UUID::toString)
                    .collect(java.util.stream.Collectors.joining(",")));
        }
        return snapshot(roomRepository.save(room));
    }

    private void validatePawnTransition(OnlineMatchRoom room, UUID senderId,
                                        UUID nextTurnOwnerId, Integer diceValue,
                                        int rollOpportunityId,
                                        boolean isDiceRolling, String stateJson) {
        try {
            JsonNode next = objectMapper.readTree(stateJson);
            JsonNode previous = room.getLatestStateJson() == null
                    ? null : objectMapper.readTree(room.getLatestStateJson());
            if (!room.getGameMode().equals(next.path("gameMode").asText("CLASSIC"))) {
                throw invalidState();
            }
            Map<String, Integer> before = pawnPositions(previous);
            Map<String, Integer> after = pawnPositions(next);
            int expectedPawns = room.getPlayerCount() * 4;
            if (after.size() != expectedPawns || (!before.isEmpty() && !before.keySet().equals(after.keySet()))) {
                throw invalidState();
            }
            if (next.path("isGameOver").asBoolean()
                    && "CLASSIC".equals(room.getGameMode())
                    && !hasFinishedPlayer(next)) {
                throw invalidState();
            }
            if (previous == null) {
                if (!room.getTurnOwnerId().equals(senderId)
                        || !senderId.equals(activePlayerId(next))
                        || !hasExpectedOnlineSeats(next, room)
                        || next.path("isGameOver").asBoolean()) throw invalidState();
                if (!hasExpectedInitialPawnPositions(next, room)) throw invalidState();
                return;
            }
            if (before.size() != expectedPawns) throw invalidState();

            List<String> changed = before.keySet().stream()
                    .filter(key -> !before.get(key).equals(after.get(key))).toList();
            if (previous.path("isGameOver").asBoolean() && !changed.isEmpty()) {
                throw invalidState();
            }
            if (changed.isEmpty()) {
                if (previous.path("isGameOver").asBoolean()) {
                    if (!next.path("isGameOver").asBoolean()
                            || !sameWinnerIds(previous, next)
                            || !nextTurnOwnerId.equals(activePlayerId(next))) {
                        throw invalidState();
                    }
                    return;
                }
                UUID nextActivePlayer = activePlayerId(next);
                if (nextActivePlayer == null || !nextActivePlayer.equals(nextTurnOwnerId)) {
                    throw invalidState();
                }
                if (nextTurnOwnerId.equals(senderId)) {
                    if (next.path("isGameOver").asBoolean()) {
                        if ("CLASSIC".equals(room.getGameMode())
                                && hasFinishedPlayer(next)) return;
                        throw invalidState();
                    }
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
            boolean firstKillWin = "FIRST_KILL".equals(room.getGameMode())
                    && !captured.isEmpty();
            if ("FIRST_KILL".equals(room.getGameMode())) {
                if (firstKillWin != next.path("isGameOver").asBoolean()
                        || (firstKillWin && !isSoleWinner(next, senderId))) {
                    throw invalidState();
                }
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
            if (next.path("isGameOver").asBoolean()
                    && "CLASSIC".equals(room.getGameMode())
                    && !hasFinishedPlayer(next)) {
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

    private boolean hasExpectedInitialPawnPositions(JsonNode state, OnlineMatchRoom room) {
        boolean firstKill = "FIRST_KILL".equals(room.getGameMode());
        for (JsonNode player : state.path("players")) {
            JsonNode pawns = player.path("pawns");
            if (!pawns.isArray() || pawns.size() != 4) return false;
            for (JsonNode pawn : pawns) {
                int pawnId = pawn.path("id").asInt(-1);
                int expectedStep = firstKill && pawnId >= 0 && pawnId < 2 ? 0 : -1;
                if (pawn.path("stepCount").asInt(Integer.MIN_VALUE) != expectedStep) {
                    return false;
                }
            }
        }
        return true;
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

    private boolean isSoleWinner(JsonNode state, UUID winnerId) {
        JsonNode winners = state.path("winnerIds");
        return winners.isArray() && winners.size() == 1
                && winnerId.toString().equals(winners.get(0).asText());
    }

    private boolean sameWinnerIds(JsonNode previous, JsonNode next) {
        return previous.path("winnerIds").toString()
                .equals(next.path("winnerIds").toString());
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
        if (isRoomGameOver(room)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "This online match has already ended.");
        }
        try {
            int diceValue = diceRandom.nextInt(6) + 1;
            int result = room.issueDiceRoll(playerId, rollOpportunityId, diceValue);
            roomRepository.save(room);
            return result;
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    private boolean isRoomGameOver(OnlineMatchRoom room) {
        if (room.getLatestStateJson() == null) return false;
        try {
            return objectMapper.readTree(room.getLatestStateJson())
                    .path("isGameOver").asBoolean();
        } catch (Exception exception) {
            return true;
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
        room.touchPlayer(playerId);
        roomRepository.save(room);
    }

    private OnlineMatchRoom findActiveRoom(UUID playerId, int playerCount,
                                           String sessionId) {
        List<OnlineMatchRoom> rooms = roomRepository.findActiveForPlayer(playerId, ACTIVE_STATUSES);
        return rooms.stream()
                .filter(room -> room.getPlayerCount() == playerCount)
                .filter(room -> sessionId.equals(room.sessionIdOf(playerId)))
                .findFirst().orElse(null);
    }

    private void deleteTicketForSession(UUID playerId, String sessionId) {
        MatchmakingTicket ticket = ticketRepository.findByPlayerIdForUpdate(playerId)
                .orElse(null);
        if (ticket != null && sessionId.equals(ticket.getSessionId())) {
            ticketRepository.delete(ticket);
        }
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

    private MatchmakingResponseDto responseFor(OnlineMatchRoom room, UUID playerId) {
        UUID opponentId = room.opponentOf(playerId);
        if (opponentId == null) return searchingResponse();
        MatchmakingResponseDto response = new MatchmakingResponseDto(
                true, room.getRoomId(), opponentId,
                room.nameOf(opponentId), room.avatarOf(opponentId),
                room.countryOf(opponentId), room.flagOf(opponentId), "Match Found!");
        response.setPlayerId(playerId);
        response.setSessionId(room.sessionIdOf(playerId));
        response.setPlayerCount(room.getPlayerCount());
        response.setGameMode(room.getGameMode());
        response.setPlayers(room.getPlayers().stream().map(player -> {
            PlayerWallet wallet = walletRepository.findByPlayerId(player.id()).orElse(null);
            return new MatchmakingResponseDto.MatchPlayerDto(
                    player.id(), player.name(), player.avatarUrl(), player.country(),
                    player.countryFlag(), player.color(),
                    wallet == null ? 0 : wallet.getBalance(),
                    wallet == null ? 0 : wallet.getDiamonds());
        }).toList());
        return response;
    }

    private static RoomSnapshot snapshot(OnlineMatchRoom room) {
        List<UUID> acceptedPlayers = java.util.Arrays.stream(
                        room.getRematchAcceptedPlayerIds().split(","))
                .filter(value -> !value.isBlank()).map(UUID::fromString).toList();
        return new RoomSnapshot(room.getRoomId(), room.getStatus(),
                room.getPlayerIds(), room.getPlayerIds().stream().filter(room::isConnected).toList(),
                room.getTurnOwnerId(), room.getStateRevision(),
                room.getLatestStateSenderId(), room.getLatestStateJson(),
                room.getRematchRevision(), room.getRematchRoundId(), room.getRematchRequesterId(),
                room.getRematchStatus(), acceptedPlayers);
    }

    private static MatchmakingResponseDto searchingResponse() {
        return new MatchmakingResponseDto(false, null, null, null, null, null, null,
                "Searching for online players...");
    }

    private static MatchmakingResponseDto searchingResponse(String gameMode, int playerCount) {
        MatchmakingResponseDto response = searchingResponse();
        response.setGameMode(gameMode);
        response.setPlayerCount(playerCount);
        return response;
    }

    private static MatchmakingResponseDto insufficientFunds() {
        return new MatchmakingResponseDto(false, null, null, null, null, null, null,
                "Insufficient gold coins for entry fee.");
    }

    private static String nonBlank(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
