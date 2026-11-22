package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.Instant;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

@Entity
@Table(name = "online_match_rooms")
public class OnlineMatchRoom {
    private static final Duration CONNECTION_LEASE = Duration.ofSeconds(45);

    public enum Status { MATCHED, READY, FINISHED, CANCELLED }
    public enum RematchStatus { NONE, REQUESTED, DECLINED, ACCEPTED }

    @Id
    @Column(name = "room_id", length = 64)
    private String roomId;

    @Column(name = "player_a_id", nullable = false)
    private UUID playerAId;
    @Column(name = "player_a_name", nullable = false, length = 100)
    private String playerAName;
    @Column(name = "player_a_avatar", length = 500)
    private String playerAAvatar;
    @Column(name = "player_a_country", length = 100)
    private String playerACountry;
    @Column(name = "player_a_flag", length = 16)
    private String playerAFlag;

    @Column(name = "player_b_id", nullable = false)
    private UUID playerBId;
    @Column(name = "player_b_name", nullable = false, length = 100)
    private String playerBName;
    @Column(name = "player_b_avatar", length = 500)
    private String playerBAvatar;
    @Column(name = "player_b_country", length = 100)
    private String playerBCountry;
    @Column(name = "player_b_flag", length = 16)
    private String playerBFlag;

    @Column(name = "player_c_id")
    private UUID playerCId;
    @Column(name = "player_c_name", length = 100)
    private String playerCName;
    @Column(name = "player_c_avatar", length = 500)
    private String playerCAvatar;
    @Column(name = "player_c_country", length = 100)
    private String playerCCountry;
    @Column(name = "player_c_flag", length = 16)
    private String playerCFlag;
    @Column(name = "player_c_color", length = 8)
    private String playerCColor;

    @Column(name = "player_d_id")
    private UUID playerDId;
    @Column(name = "player_d_name", length = 100)
    private String playerDName;
    @Column(name = "player_d_avatar", length = 500)
    private String playerDAvatar;
    @Column(name = "player_d_country", length = 100)
    private String playerDCountry;
    @Column(name = "player_d_flag", length = 16)
    private String playerDFlag;
    @Column(name = "player_d_color", length = 8)
    private String playerDColor;

    @Column(name = "player_a_color", nullable = false, length = 8)
    private String playerAColor = "red";
    @Column(name = "player_b_color", nullable = false, length = 8)
    private String playerBColor = "yellow";
    @Column(name = "player_count", nullable = false)
    private int playerCount = 2;

    @Column(name = "game_mode", nullable = false, length = 16)
    private String gameMode = "CLASSIC";

    @Column(name = "player_a_session_id", length = 64)
    private String playerASessionId;
    @Column(name = "player_b_session_id", length = 64)
    private String playerBSessionId;
    @Column(name = "player_c_session_id", length = 64)
    private String playerCSessionId;
    @Column(name = "player_d_session_id", length = 64)
    private String playerDSessionId;

    @Column(name = "entry_fee", nullable = false)
    private long entryFee;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private Status status = Status.MATCHED;

    @Column(name = "player_a_connected", nullable = false)
    private boolean playerAConnected;
    @Column(name = "player_b_connected", nullable = false)
    private boolean playerBConnected;
    @Column(name = "player_c_connected", nullable = false)
    private boolean playerCConnected;
    @Column(name = "player_d_connected", nullable = false)
    private boolean playerDConnected;

    @Column(name = "player_a_last_seen_at")
    private Instant playerALastSeenAt;
    @Column(name = "player_b_last_seen_at")
    private Instant playerBLastSeenAt;
    @Column(name = "player_c_last_seen_at")
    private Instant playerCLastSeenAt;
    @Column(name = "player_d_last_seen_at")
    private Instant playerDLastSeenAt;

    @Column(name = "turn_owner_id")
    private UUID turnOwnerId;

    @Column(name = "authoritative_roll_opportunity_id", nullable = false)
    private int authoritativeRollOpportunityId;
    @Column(name = "authoritative_roll_player_id")
    private UUID authoritativeRollPlayerId;
    @Column(name = "authoritative_dice_value")
    private Integer authoritativeDiceValue;

    @Column(name = "latest_state_json", columnDefinition = "TEXT")
    private String latestStateJson;
    @Column(name = "latest_state_sender_id")
    private UUID latestStateSenderId;
    @Column(name = "state_revision", nullable = false)
    private long stateRevision;

    // Nullable for compatibility with rooms created before rematch support.
    @Column(name = "rematch_revision")
    private Long rematchRevision = 0L;
    @Column(name = "rematch_round_id")
    private UUID rematchRoundId;
    @Column(name = "rematch_requester_id")
    private UUID rematchRequesterId;
    @Enumerated(EnumType.STRING)
    @Column(name = "rematch_status", length = 16)
    private RematchStatus rematchStatus = RematchStatus.NONE;
    @Column(name = "rematch_accepted_player_ids", columnDefinition = "TEXT")
    private String rematchAcceptedPlayerIds = "";

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    @Version
    private long version;

    protected OnlineMatchRoom() {}

    public OnlineMatchRoom(String roomId, List<MatchmakingTicket> tickets, long entryFee) {
        if (tickets.size() != 2 && tickets.size() != 4) {
            throw new IllegalArgumentException("Online rooms require two or four players.");
        }
        playerCount = tickets.size();
        gameMode = tickets.getFirst().getGameMode();
        if (tickets.stream().anyMatch(ticket -> !gameMode.equals(ticket.getGameMode()))) {
            throw new IllegalArgumentException("Online room players must choose the same game mode.");
        }
        List<String> availableColors = new ArrayList<>(List.of("red", "green", "yellow", "blue"));
        List<String> assignedColors = new ArrayList<>();
        if (tickets.size() == 2) {
            String firstColor = tickets.get(0).getSelectedColor();
            // Keep the authoritative seats opposite so two-player rules remain
            // rotationally symmetric. Each client maps these canonical seats
            // to its own selected color when presenting the match.
            String secondColor = switch (firstColor) {
                case "red" -> "yellow";
                case "green" -> "blue";
                case "yellow" -> "red";
                default -> "green";
            };
            assignedColors.add(firstColor);
            assignedColors.add(secondColor);
        } else {
            for (MatchmakingTicket ticket : tickets) {
                String color = ticket.getSelectedColor();
                if (!availableColors.remove(color)) {
                    color = availableColors.removeFirst();
                }
                assignedColors.add(color);
            }
        }
        MatchmakingTicket playerA = tickets.get(0);
        MatchmakingTicket playerB = tickets.get(1);
        this.roomId = roomId;
        this.playerAId = playerA.getPlayerId();
        this.playerASessionId = playerA.getSessionId();
        this.playerAName = playerA.getDisplayName();
        this.playerAAvatar = playerA.getAvatarUrl();
        this.playerACountry = playerA.getCountry();
        this.playerAFlag = playerA.getCountryFlag();
        this.playerBId = playerB.getPlayerId();
        this.playerBSessionId = playerB.getSessionId();
        this.playerBName = playerB.getDisplayName();
        this.playerBAvatar = playerB.getAvatarUrl();
        this.playerBCountry = playerB.getCountry();
        this.playerBFlag = playerB.getCountryFlag();
        playerAColor = assignedColors.get(0);
        playerBColor = assignedColors.get(1);
        if (tickets.size() == 4) {
            MatchmakingTicket playerC = tickets.get(2);
            MatchmakingTicket playerD = tickets.get(3);
            playerCId = playerC.getPlayerId(); playerCName = playerC.getDisplayName();
            playerCAvatar = playerC.getAvatarUrl(); playerCCountry = playerC.getCountry();
            playerCFlag = playerC.getCountryFlag(); playerCColor = assignedColors.get(2);
            playerCSessionId = playerC.getSessionId();
            playerDId = playerD.getPlayerId(); playerDName = playerD.getDisplayName();
            playerDAvatar = playerD.getAvatarUrl(); playerDCountry = playerD.getCountry();
            playerDFlag = playerD.getCountryFlag(); playerDColor = assignedColors.get(3);
            playerDSessionId = playerD.getSessionId();
        }
        this.entryFee = entryFee;
    }

    public OnlineMatchRoom(String roomId, MatchmakingTicket playerA,
                           MatchmakingTicket playerB, long entryFee) {
        this(roomId, List.of(playerA, playerB), entryFee);
    }

    public String getRoomId() { return roomId; }
    public UUID getPlayerAId() { return playerAId; }
    public String getPlayerAName() { return playerAName; }
    public String getPlayerAAvatar() { return playerAAvatar; }
    public String getPlayerACountry() { return playerACountry; }
    public String getPlayerAFlag() { return playerAFlag; }
    public UUID getPlayerBId() { return playerBId; }
    public String getPlayerBName() { return playerBName; }
    public String getPlayerBAvatar() { return playerBAvatar; }
    public String getPlayerBCountry() { return playerBCountry; }
    public String getPlayerBFlag() { return playerBFlag; }
    public int getPlayerCount() { return playerCount; }
    public String getGameMode() { return gameMode == null ? "CLASSIC" : gameMode; }
    public List<UUID> getPlayerIds() {
        List<UUID> ids = new ArrayList<>(List.of(playerAId, playerBId));
        if (playerCId != null) ids.add(playerCId);
        if (playerDId != null) ids.add(playerDId);
        return ids;
    }
    public List<MatchPlayer> getPlayers() {
        List<MatchPlayer> players = new ArrayList<>();
        players.add(new MatchPlayer(playerAId, playerAName, playerAAvatar, playerACountry, playerAFlag, playerAColor));
        players.add(new MatchPlayer(playerBId, playerBName, playerBAvatar, playerBCountry, playerBFlag, playerBColor));
        if (playerCId != null) players.add(new MatchPlayer(playerCId, playerCName, playerCAvatar, playerCCountry, playerCFlag, playerCColor));
        if (playerDId != null) players.add(new MatchPlayer(playerDId, playerDName, playerDAvatar, playerDCountry, playerDFlag, playerDColor));
        return players;
    }
    public record MatchPlayer(UUID id, String name, String avatarUrl, String country, String countryFlag, String color) {}
    public UUID playerForColor(String color) { return getPlayers().stream().filter(p -> p.color().equals(color)).map(MatchPlayer::id).findFirst().orElse(null); }
    public long getEntryFee() { return entryFee; }
    public Status getStatus() { return status; }
    public boolean isPlayerAConnected() { return playerAConnected; }
    public boolean isPlayerBConnected() { return playerBConnected; }
    public UUID getTurnOwnerId() { return turnOwnerId; }
    public int getAuthoritativeRollOpportunityId() { return authoritativeRollOpportunityId; }
    public UUID getAuthoritativeRollPlayerId() { return authoritativeRollPlayerId; }
    public Integer getAuthoritativeDiceValue() { return authoritativeDiceValue; }
    public String getLatestStateJson() { return latestStateJson; }
    public UUID getLatestStateSenderId() { return latestStateSenderId; }
    public long getStateRevision() { return stateRevision; }
    public long getRematchRevision() { return rematchRevision == null ? 0L : rematchRevision; }
    public UUID getRematchRoundId() { return rematchRoundId; }
    public UUID getRematchRequesterId() { return rematchRequesterId; }
    public RematchStatus getRematchStatus() {
        return rematchStatus == null ? RematchStatus.NONE : rematchStatus;
    }
    public String getRematchAcceptedPlayerIds() {
        return rematchAcceptedPlayerIds == null ? "" : rematchAcceptedPlayerIds;
    }

    public boolean contains(UUID playerId) { return getPlayerIds().contains(playerId); }

    public String sessionIdOf(UUID playerId) {
        if (playerAId.equals(playerId)) return playerASessionId;
        if (playerBId.equals(playerId)) return playerBSessionId;
        if (playerCId != null && playerCId.equals(playerId)) return playerCSessionId;
        if (playerDId != null && playerDId.equals(playerId)) return playerDSessionId;
        return null;
    }

    public UUID opponentOf(UUID playerId) {
        List<UUID> ids = getPlayerIds(); int i = ids.indexOf(playerId);
        return i < 0 ? null : ids.get((i + 1) % ids.size());
    }

    public String nameOf(UUID playerId) {
        return getPlayers().stream().filter(p -> p.id().equals(playerId))
                .map(MatchPlayer::name).filter(Objects::nonNull).findFirst().orElse(null);
    }

    public String avatarOf(UUID playerId) {
        return getPlayers().stream().filter(p -> p.id().equals(playerId))
                .map(MatchPlayer::avatarUrl).filter(Objects::nonNull).findFirst().orElse(null);
    }

    public String countryOf(UUID playerId) {
        return getPlayers().stream().filter(p -> p.id().equals(playerId))
                .map(MatchPlayer::country).filter(Objects::nonNull).findFirst().orElse(null);
    }

    public String flagOf(UUID playerId) {
        return getPlayers().stream().filter(p -> p.id().equals(playerId))
                .map(MatchPlayer::countryFlag).filter(Objects::nonNull).findFirst().orElse(null);
    }

    public boolean isConnected(UUID playerId) {
        if (playerAId.equals(playerId)) return isFresh(playerAConnected, playerALastSeenAt);
        if (playerBId.equals(playerId)) return isFresh(playerBConnected, playerBLastSeenAt);
        if (playerCId != null && playerCId.equals(playerId)) return isFresh(playerCConnected, playerCLastSeenAt);
        return playerDId != null && playerDId.equals(playerId)
                && isFresh(playerDConnected, playerDLastSeenAt);
    }

    public boolean isAbandoned(Instant now) {
        // A room that never received its first game state was never actually
        // played. Expire it from creation time even if a client kept sending
        // pings after failing to finish the room handshake.
        if (latestStateJson == null && createdAt.isBefore(now.minus(CONNECTION_LEASE))) {
            return true;
        }
        boolean hasLivePlayer = getPlayerIds().stream().anyMatch(this::isConnected);
        return !hasLivePlayer && updatedAt.isBefore(now.minus(CONNECTION_LEASE));
    }

    public void connect(UUID playerId) {
        Instant now = Instant.now();
        expireStaleConnections(now);
        if (playerAId.equals(playerId)) {
            playerAConnected = true;
            playerALastSeenAt = now;
        } else if (playerBId.equals(playerId)) {
            playerBConnected = true;
            playerBLastSeenAt = now;
        } else if (playerCId != null && playerCId.equals(playerId)) {
            playerCConnected = true;
            playerCLastSeenAt = now;
        } else if (playerDId != null && playerDId.equals(playerId)) {
            playerDConnected = true;
            playerDLastSeenAt = now;
        }
        if (getPlayerIds().stream().allMatch(this::isConnected)) {
            status = Status.READY;
            if (turnOwnerId == null) {
                // Match the clients' String.compareTo ordering exactly. UUID's
                // natural comparator uses signed 64-bit halves and can select a
                // different first player than lexicographic ID ordering.
                turnOwnerId = getPlayerIds().stream()
                        .min(Comparator.comparing(UUID::toString))
                        .orElse(playerAId);
            }
        } else if (latestStateJson == null) {
            status = Status.MATCHED;
        }
        touch();
    }

    public void disconnect(UUID playerId) {
        if (playerAId.equals(playerId)) {
            playerAConnected = false;
            playerALastSeenAt = null;
        } else if (playerBId.equals(playerId)) {
            playerBConnected = false;
            playerBLastSeenAt = null;
        } else if (playerCId != null && playerCId.equals(playerId)) {
            playerCConnected = false;
            playerCLastSeenAt = null;
        } else if (playerDId != null && playerDId.equals(playerId)) {
            playerDConnected = false;
            playerDLastSeenAt = null;
        }
        if (latestStateJson == null) status = Status.MATCHED;
        touch();
    }

    public void touchPlayer(UUID playerId) {
        Instant now = Instant.now();
        if (playerAId.equals(playerId) && playerAConnected) playerALastSeenAt = now;
        else if (playerBId.equals(playerId) && playerBConnected) playerBLastSeenAt = now;
        else if (playerCId != null && playerCId.equals(playerId) && playerCConnected) playerCLastSeenAt = now;
        else if (playerDId != null && playerDId.equals(playerId) && playerDConnected) playerDLastSeenAt = now;
        touch();
    }

    private boolean isFresh(boolean connected, Instant lastSeenAt) {
        return connected && lastSeenAt != null
                && lastSeenAt.isAfter(Instant.now().minus(CONNECTION_LEASE));
    }

    private void expireStaleConnections(Instant now) {
        if (!isFreshAt(playerAConnected, playerALastSeenAt, now)) {
            playerAConnected = false;
            playerALastSeenAt = null;
        }
        if (!isFreshAt(playerBConnected, playerBLastSeenAt, now)) {
            playerBConnected = false;
            playerBLastSeenAt = null;
        }
        if (playerCId != null && !isFreshAt(playerCConnected, playerCLastSeenAt, now)) {
            playerCConnected = false;
            playerCLastSeenAt = null;
        }
        if (playerDId != null && !isFreshAt(playerDConnected, playerDLastSeenAt, now)) {
            playerDConnected = false;
            playerDLastSeenAt = null;
        }
    }

    private boolean isFreshAt(boolean connected, Instant lastSeenAt, Instant now) {
        return connected && lastSeenAt != null
                && lastSeenAt.isAfter(now.minus(CONNECTION_LEASE));
    }

    public void touch() { updatedAt = Instant.now(); }

    public void recordState(UUID senderId, UUID nextTurnOwnerId, String stateJson) {
        latestStateJson = stateJson;
        latestStateSenderId = senderId;
        stateRevision++;
        turnOwnerId = nextTurnOwnerId;
        touch();
    }

    public void requestRematch(UUID requesterId) {
        rematchRoundId = UUID.randomUUID();
        rematchRequesterId = requesterId;
        rematchAcceptedPlayerIds = requesterId.toString();
        rematchStatus = RematchStatus.REQUESTED;
        rematchRevision = getRematchRevision() + 1;
        touch();
    }

    public void recordRematchDeclined() {
        rematchStatus = RematchStatus.DECLINED;
        rematchRevision = getRematchRevision() + 1;
        touch();
    }

    public void recordRematchAccepted(String acceptedPlayerIds) {
        rematchAcceptedPlayerIds = acceptedPlayerIds;
        rematchRevision = getRematchRevision() + 1;
        touch();
    }

    public void startAcceptedRematch(UUID firstPlayerId) {
        rematchStatus = RematchStatus.ACCEPTED;
        rematchRevision = getRematchRevision() + 1;
        latestStateJson = null;
        latestStateSenderId = null;
        turnOwnerId = firstPlayerId;
        authoritativeRollOpportunityId = 0;
        authoritativeRollPlayerId = null;
        authoritativeDiceValue = null;
        touch();
    }

    public int issueDiceRoll(UUID playerId, int rollOpportunityId, int diceValue) {
        if (status != Status.READY || !playerId.equals(turnOwnerId)) {
            throw new IllegalStateException("Only the current player can roll the dice.");
        }
        if (rollOpportunityId == authoritativeRollOpportunityId
                && playerId.equals(authoritativeRollPlayerId)
                && authoritativeDiceValue != null) {
            return authoritativeDiceValue;
        }
        if (rollOpportunityId != authoritativeRollOpportunityId + 1) {
            throw new IllegalStateException("The dice roll opportunity is stale or out of sequence.");
        }
        authoritativeRollOpportunityId = rollOpportunityId;
        authoritativeRollPlayerId = playerId;
        authoritativeDiceValue = diceValue;
        touch();
        return diceValue;
    }

    public boolean matchesAuthoritativeRoll(UUID playerId, int rollOpportunityId, int diceValue) {
        return playerId.equals(authoritativeRollPlayerId)
                && rollOpportunityId == authoritativeRollOpportunityId
                && authoritativeDiceValue != null
                && diceValue == authoritativeDiceValue;
    }

    public boolean hasAuthoritativeRoll(UUID playerId, int diceValue) {
        return playerId.equals(authoritativeRollPlayerId)
                && authoritativeDiceValue != null
                && authoritativeDiceValue == diceValue;
    }

    public void finish() {
        status = Status.FINISHED;
        touch();
    }

    public void cancel() {
        status = Status.CANCELLED;
        touch();
    }
}
