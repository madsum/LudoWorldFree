package com.ludoworldfree.backend.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ludoworldfree.backend.dto.FriendPlayRoomSeatDto;
import com.ludoworldfree.backend.dto.MatchmakingResponseDto;
import com.ludoworldfree.backend.model.FriendPlayRoom;
import com.ludoworldfree.backend.repository.FriendPlayRoomRepository;
import com.ludoworldfree.backend.repository.PlayerWalletRepository;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class FriendPlayRoomService {
    private static final Set<String> COLORS = Set.of("red", "green", "yellow", "blue");
    private static final Set<String> MODES = Set.of("CLASSIC", "FIRST_KILL");
    private static final TypeReference<List<FriendPlayRoomSeatDto>> SEATS_TYPE =
            new TypeReference<>() {};

    public record CreateRequest(String displayName, String avatarUrl, String country,
                                String countryFlag, long entryFee, int playerCount,
                                String selectedColor, String gameMode, String sessionId,
                                String tokenSkinId, boolean voiceChat) {}

    public record JoinRequest(String displayName, String avatarUrl, String country,
                              String countryFlag, String selectedColor, String sessionId,
                              String tokenSkinId) {}

    private final FriendPlayRoomRepository rooms;
    private final PlayerWalletRepository wallets;
    private final MatchmakingService matchmaking;
    private final ObjectMapper objectMapper;
    private final SecureRandom random = new SecureRandom();

    public FriendPlayRoomService(FriendPlayRoomRepository rooms,
                                 PlayerWalletRepository wallets,
                                 MatchmakingService matchmaking,
                                 ObjectMapper objectMapper) {
        this.rooms = rooms;
        this.wallets = wallets;
        this.matchmaking = matchmaking;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public Map<String, Object> create(UUID hostId, CreateRequest request) {
        validateSettings(request.playerCount(), request.entryFee(), request.gameMode());
        if (matchmaking.isPlayerInActiveRoom(hostId)) {
            throw conflict("Leave your current online game before creating a room.");
        }
        String color = normalizeColor(request.selectedColor());
        String sessionId = validateSession(request.sessionId());
        long balance = wallets.findByPlayerId(hostId).map(w -> w.getBalance()).orElse(2000L);
        if (balance < request.entryFee()) {
            throw conflict("You do not have enough coins for this entry amount.");
        }

        String code = nextCode();
        String roomId = UUID.randomUUID().toString();
        FriendPlayRoomSeatDto host = new FriendPlayRoomSeatDto(hostId,
                nonBlank(request.displayName(), "Player"), request.avatarUrl(),
                nonBlank(request.country(), "World"), nonBlank(request.countryFlag(), "🌐"),
                color, sessionId, nonBlank(request.tokenSkinId(), "default"));
        FriendPlayRoom room = new FriendPlayRoom(roomId, code, hostId,
                request.playerCount(), request.entryFee(), request.gameMode().toUpperCase(),
                request.voiceChat(), writeSeats(List.of(host)),
                Instant.now().plus(30, ChronoUnit.MINUTES));
        rooms.saveAndFlush(room);
        return response(room, List.of(host), null);
    }

    @Transactional
    public Map<String, Object> join(String roomCode, UUID playerId, JoinRequest request) {
        FriendPlayRoom room = rooms.findByCodeForUpdate(normalizeCode(roomCode))
                .orElseThrow(() -> notFound("That room code was not found."));
        List<FriendPlayRoomSeatDto> seats = readSeats(room);
        if (seats.stream().anyMatch(seat -> seat.playerId().equals(playerId))) {
            return response(room, seats, matchFor(room, seats, playerId));
        }
        ensureOpen(room);
        if (matchmaking.isPlayerInActiveRoom(playerId)) {
            throw conflict("Leave your current online game before joining a room.");
        }
        if (seats.size() >= room.getPlayerCount()) throw conflict("This room is full.");

        String color = normalizeColor(request.selectedColor());
        if (seats.stream().anyMatch(seat -> seat.selectedColor().equals(color))) {
            throw conflict("That color is already taken. Choose another color.");
        }
        String sessionId = validateSession(request.sessionId());
        long balance = wallets.findByPlayerId(playerId).map(w -> w.getBalance()).orElse(2000L);
        if (balance < room.getEntryFee()) {
            throw conflict("You do not have enough coins for this entry amount.");
        }
        seats = new ArrayList<>(seats);
        seats.add(new FriendPlayRoomSeatDto(playerId,
                nonBlank(request.displayName(), "Player"), request.avatarUrl(),
                nonBlank(request.country(), "World"), nonBlank(request.countryFlag(), "🌐"),
                color, sessionId, nonBlank(request.tokenSkinId(), "default")));
        room.setSeatsJson(writeSeats(seats));
        rooms.saveAndFlush(room);
        return response(room, seats, null);
    }

    @Transactional(readOnly = true)
    public Map<String, Object> preview(String roomCode) {
        FriendPlayRoom room = rooms.findByRoomCode(normalizeCode(roomCode))
                .orElseThrow(() -> notFound("That room code was not found."));
        if (!room.getStatus().equals(FriendPlayRoom.OPEN)
                || room.getExpiresAt().isBefore(Instant.now())) {
            throw conflict("This room is no longer available.");
        }
        return response(room, readSeats(room), null);
    }

    @Transactional(readOnly = true)
    public Map<String, Object> status(String roomCode, UUID playerId) {
        FriendPlayRoom room = rooms.findByRoomCode(normalizeCode(roomCode))
                .orElseThrow(() -> notFound("That room code was not found."));
        List<FriendPlayRoomSeatDto> seats = readSeats(room);
        if (seats.stream().noneMatch(seat -> seat.playerId().equals(playerId))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Join this room before requesting its updates.");
        }
        if (room.getStatus().equals(FriendPlayRoom.OPEN) && room.getExpiresAt().isBefore(Instant.now())) {
            throw conflict("This room has expired.");
        }
        return response(room, seats, matchFor(room, seats, playerId));
    }

    @Transactional
    public Map<String, Object> start(String roomCode, UUID playerId) {
        FriendPlayRoom room = rooms.findByCodeForUpdate(normalizeCode(roomCode))
                .orElseThrow(() -> notFound("That room code was not found."));
        List<FriendPlayRoomSeatDto> seats = readSeats(room);
        if (!room.getHostPlayerId().equals(playerId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Only the room host can start the match.");
        }
        if (room.getStatus().equals(FriendPlayRoom.STARTED)) {
            return response(room, seats, matchFor(room, seats, playerId));
        }
        ensureOpen(room);
        if (seats.size() != room.getPlayerCount()) {
            throw conflict("Wait until every player slot is filled before starting.");
        }
        MatchmakingResponseDto match = matchmaking.createFriendPlayRoomMatch(
                room.getRoomId(), room.getEntryFee(), room.getGameMode(), seats);
        room.markStarted();
        rooms.saveAndFlush(room);
        return response(room, seats, completeMatch(room, seats, playerId, match));
    }

    @Transactional
    public void close(String roomCode, UUID playerId) {
        FriendPlayRoom room = rooms.findByCodeForUpdate(normalizeCode(roomCode))
                .orElseThrow(() -> notFound("That room code was not found."));
        if (!room.getHostPlayerId().equals(playerId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Only the room host can close it.");
        }
        if (room.getStatus().equals(FriendPlayRoom.OPEN)) {
            room.close();
            rooms.save(room);
        }
    }

    @Transactional
    public void leave(String roomCode, UUID playerId) {
        FriendPlayRoom room = rooms.findByCodeForUpdate(normalizeCode(roomCode))
                .orElseThrow(() -> notFound("That room code was not found."));
        if (!room.getStatus().equals(FriendPlayRoom.OPEN)) return;
        if (room.getHostPlayerId().equals(playerId)) {
            room.close();
        } else {
            List<FriendPlayRoomSeatDto> seats = new ArrayList<>(readSeats(room));
            seats.removeIf(seat -> seat.playerId().equals(playerId));
            room.setSeatsJson(writeSeats(seats));
        }
        rooms.save(room);
    }

    @Scheduled(fixedDelayString = "${friend-room.cleanup-millis:60000}")
    @Transactional
    public void expireRooms() {
        List<FriendPlayRoom> expired = rooms.findAllByStatusAndExpiresAtBefore(
                FriendPlayRoom.OPEN, Instant.now());
        expired.forEach(FriendPlayRoom::close);
        rooms.saveAll(expired);
    }

    private Map<String, Object> response(FriendPlayRoom room,
                                         List<FriendPlayRoomSeatDto> seats,
                                         MatchmakingResponseDto match) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("roomCode", room.getRoomCode());
        result.put("roomId", room.getRoomId());
        result.put("hostPlayerId", room.getHostPlayerId());
        result.put("playerCount", room.getPlayerCount());
        result.put("entryFee", room.getEntryFee());
        result.put("gameMode", room.getGameMode());
        result.put("voiceChat", room.isVoiceChat());
        result.put("status", room.getStatus());
        result.put("started", room.getStatus().equals(FriendPlayRoom.STARTED));
        result.put("expiresAt", room.getExpiresAt());
        result.put("seats", seats.stream().map(this::seatView).toList());
        if (match != null) result.put("match", match);
        return result;
    }

    private Map<String, Object> seatView(FriendPlayRoomSeatDto seat) {
        Map<String, Object> view = new LinkedHashMap<>();
        view.put("playerId", seat.playerId());
        view.put("displayName", seat.displayName());
        view.put("avatarUrl", seat.avatarUrl());
        view.put("country", seat.country());
        view.put("countryFlag", seat.countryFlag());
        view.put("selectedColor", seat.selectedColor());
        view.put("tokenSkinId", seat.tokenSkinId());
        return view;
    }

    private MatchmakingResponseDto matchFor(FriendPlayRoom room,
                                            List<FriendPlayRoomSeatDto> seats,
                                            UUID playerId) {
        if (!room.getStatus().equals(FriendPlayRoom.STARTED)) return null;
        MatchmakingResponseDto match = matchmaking.responseForBuddyRoom(
                room.getRoomId(), playerId);
        return completeMatch(room, seats, playerId,
                match == null ? new MatchmakingResponseDto() : match);
    }

    private MatchmakingResponseDto completeMatch(FriendPlayRoom room,
                                                  List<FriendPlayRoomSeatDto> seats,
                                                  UUID playerId,
                                                  MatchmakingResponseDto match) {
        FriendPlayRoomSeatDto currentSeat = seats.stream()
                .filter(seat -> seat.playerId().equals(playerId))
                .findFirst()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.FORBIDDEN,
                        "You are not a player in this room."));
        match.setMatchFound(true);
        match.setRoomId(room.getRoomId());
        match.setPlayerId(playerId);
        match.setSessionId(currentSeat.sessionId());
        match.setPlayerCount(room.getPlayerCount());
        match.setGameMode(room.getGameMode());
        match.setMessage("Friend room is ready.");
        match.setPlayers(java.util.stream.IntStream.range(0, seats.size())
                .mapToObj(index -> matchPlayer(seats.get(index),
                        matchColor(room, seats, index)))
                .toList());
        return match;
    }

    private MatchmakingResponseDto.MatchPlayerDto matchPlayer(
            FriendPlayRoomSeatDto seat, String color) {
        var wallet = wallets.findByPlayerId(seat.playerId()).orElse(null);
        return new MatchmakingResponseDto.MatchPlayerDto(
                seat.playerId(), seat.displayName(), seat.avatarUrl(),
                seat.country(), seat.countryFlag(), color,
                wallet == null ? 0 : wallet.getBalance(),
                wallet == null ? 0 : wallet.getDiamonds());
    }

    private String matchColor(FriendPlayRoom room,
                              List<FriendPlayRoomSeatDto> seats,
                              int index) {
        String selected = seats.get(index).selectedColor().toLowerCase();
        if (room.getPlayerCount() != 2 || index == 0) return selected;
        return switch (seats.getFirst().selectedColor().toLowerCase()) {
            case "red" -> "yellow";
            case "green" -> "blue";
            case "yellow" -> "red";
            default -> "green";
        };
    }

    private List<FriendPlayRoomSeatDto> readSeats(FriendPlayRoom room) {
        try {
            return objectMapper.readValue(room.getSeatsJson(), SEATS_TYPE);
        } catch (Exception exception) {
            throw new IllegalStateException("Friend room seats could not be read.", exception);
        }
    }

    private String writeSeats(List<FriendPlayRoomSeatDto> seats) {
        try {
            return objectMapper.writeValueAsString(seats);
        } catch (Exception exception) {
            throw new IllegalArgumentException("Friend room seats could not be saved.", exception);
        }
    }

    private String nextCode() {
        for (int attempt = 0; attempt < 20; attempt++) {
            String code = Integer.toString(10_000_000 + random.nextInt(90_000_000));
            if (rooms.findByRoomCode(code).isEmpty()) return code;
        }
        throw new IllegalStateException("Could not allocate a unique friend room code.");
    }

    private void ensureOpen(FriendPlayRoom room) {
        if (!room.getStatus().equals(FriendPlayRoom.OPEN)) throw conflict("This room is no longer open.");
        if (room.getExpiresAt().isBefore(Instant.now())) {
            room.close();
            rooms.save(room);
            throw conflict("This room has expired.");
        }
    }

    private static void validateSettings(int playerCount, long fee, String gameMode) {
        if (playerCount != 2 && playerCount != 4) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose two or four players.");
        }
        if (fee < 100 || fee > 1_000_000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Entry amount must be between 100 and 1,000,000 coins.");
        }
        if (gameMode == null || !MODES.contains(gameMode.toUpperCase())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a supported game mode.");
        }
    }

    private static String normalizeColor(String value) {
        String color = value == null ? "" : value.toLowerCase();
        if (!COLORS.contains(color)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a valid player color.");
        }
        return color;
    }

    private static String validateSession(String value) {
        if (value == null || value.isBlank() || value.length() > 64) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A valid game session is required.");
        }
        return value.strip();
    }

    private static String normalizeCode(String code) {
        if (code == null || !code.matches("\\d{8}")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Enter the eight-digit room code.");
        }
        return code;
    }

    private static String nonBlank(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value.strip();
    }

    private static ResponseStatusException notFound(String message) {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, message);
    }

    private static ResponseStatusException conflict(String message) {
        return new ResponseStatusException(HttpStatus.CONFLICT, message);
    }
}
