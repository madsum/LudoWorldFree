package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;

@Entity
@Table(name = "friend_play_rooms")
public class FriendPlayRoom {
    public static final String OPEN = "OPEN";
    public static final String STARTED = "STARTED";
    public static final String CLOSED = "CLOSED";

    @Id
    @Column(name = "room_id", length = 64)
    private String roomId;

    @Column(name = "room_code", nullable = false, unique = true, length = 8)
    private String roomCode;

    @Column(name = "host_player_id", nullable = false)
    private java.util.UUID hostPlayerId;

    @Column(name = "player_count", nullable = false)
    private int playerCount;

    @Column(name = "entry_fee", nullable = false)
    private long entryFee;

    @Column(name = "game_mode", nullable = false, length = 16)
    private String gameMode;

    @Column(name = "voice_chat", nullable = false)
    private boolean voiceChat;

    @Column(name = "seats_json", nullable = false, columnDefinition = "TEXT")
    private String seatsJson;

    @Column(nullable = false, length = 16)
    private String status = OPEN;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    @Version
    private long version;

    protected FriendPlayRoom() {}

    public FriendPlayRoom(String roomId, String roomCode, java.util.UUID hostPlayerId,
                          int playerCount, long entryFee, String gameMode,
                          boolean voiceChat, String seatsJson, Instant expiresAt) {
        this.roomId = roomId;
        this.roomCode = roomCode;
        this.hostPlayerId = hostPlayerId;
        this.playerCount = playerCount;
        this.entryFee = entryFee;
        this.gameMode = gameMode;
        this.voiceChat = voiceChat;
        this.seatsJson = seatsJson;
        this.expiresAt = expiresAt;
    }

    public String getRoomId() { return roomId; }
    public String getRoomCode() { return roomCode; }
    public java.util.UUID getHostPlayerId() { return hostPlayerId; }
    public int getPlayerCount() { return playerCount; }
    public long getEntryFee() { return entryFee; }
    public String getGameMode() { return gameMode; }
    public boolean isVoiceChat() { return voiceChat; }
    public String getSeatsJson() { return seatsJson; }
    public String getStatus() { return status; }
    public Instant getExpiresAt() { return expiresAt; }
    public Instant getCreatedAt() { return createdAt; }

    public void setSeatsJson(String seatsJson) { this.seatsJson = seatsJson; }
    public void markStarted() { this.status = STARTED; }
    public void close() { this.status = CLOSED; }
}
