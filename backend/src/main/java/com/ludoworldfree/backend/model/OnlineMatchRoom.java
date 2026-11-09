package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "online_match_rooms")
public class OnlineMatchRoom {
    public enum Status { MATCHED, READY, FINISHED, CANCELLED }

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

    @Column(name = "entry_fee", nullable = false)
    private long entryFee;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private Status status = Status.MATCHED;

    @Column(name = "player_a_connected", nullable = false)
    private boolean playerAConnected;
    @Column(name = "player_b_connected", nullable = false)
    private boolean playerBConnected;

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

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    @Version
    private long version;

    protected OnlineMatchRoom() {}

    public OnlineMatchRoom(String roomId, MatchmakingTicket playerA,
                           MatchmakingTicket playerB, long entryFee) {
        this.roomId = roomId;
        this.playerAId = playerA.getPlayerId();
        this.playerAName = playerA.getDisplayName();
        this.playerAAvatar = playerA.getAvatarUrl();
        this.playerACountry = playerA.getCountry();
        this.playerAFlag = playerA.getCountryFlag();
        this.playerBId = playerB.getPlayerId();
        this.playerBName = playerB.getDisplayName();
        this.playerBAvatar = playerB.getAvatarUrl();
        this.playerBCountry = playerB.getCountry();
        this.playerBFlag = playerB.getCountryFlag();
        this.entryFee = entryFee;
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

    public boolean contains(UUID playerId) {
        return playerAId.equals(playerId) || playerBId.equals(playerId);
    }

    public UUID opponentOf(UUID playerId) {
        if (playerAId.equals(playerId)) return playerBId;
        if (playerBId.equals(playerId)) return playerAId;
        return null;
    }

    public String nameOf(UUID playerId) {
        return playerAId.equals(playerId) ? playerAName : playerBName;
    }

    public String avatarOf(UUID playerId) {
        return playerAId.equals(playerId) ? playerAAvatar : playerBAvatar;
    }

    public String countryOf(UUID playerId) {
        return playerAId.equals(playerId) ? playerACountry : playerBCountry;
    }

    public String flagOf(UUID playerId) {
        return playerAId.equals(playerId) ? playerAFlag : playerBFlag;
    }

    public boolean isConnected(UUID playerId) {
        return playerAId.equals(playerId) ? playerAConnected
                : playerBId.equals(playerId) && playerBConnected;
    }

    public void connect(UUID playerId) {
        if (playerAId.equals(playerId)) playerAConnected = true;
        else if (playerBId.equals(playerId)) playerBConnected = true;
        if (playerAConnected && playerBConnected) {
            status = Status.READY;
            if (turnOwnerId == null) {
                turnOwnerId = playerAId.toString().compareTo(playerBId.toString()) < 0
                        ? playerAId : playerBId;
            }
        }
        touch();
    }

    public void disconnect(UUID playerId) {
        if (playerAId.equals(playerId)) playerAConnected = false;
        else if (playerBId.equals(playerId)) playerBConnected = false;
        touch();
    }

    public void touch() { updatedAt = Instant.now(); }

    public void recordState(UUID senderId, UUID nextTurnOwnerId, String stateJson) {
        latestStateJson = stateJson;
        latestStateSenderId = senderId;
        stateRevision++;
        turnOwnerId = nextTurnOwnerId;
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
