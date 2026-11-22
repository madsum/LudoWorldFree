package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "matchmaking_tickets")
public class MatchmakingTicket {
    @Id
    @Column(name = "player_id", nullable = false)
    private UUID playerId;

    @Column(name = "display_name", nullable = false, length = 100)
    private String displayName;

    @Column(name = "avatar_url", length = 500)
    private String avatarUrl;

    @Column(length = 100)
    private String country;

    @Column(name = "country_flag", length = 16)
    private String countryFlag;

    @Column(name = "entry_fee", nullable = false)
    private long entryFee;

    @Column(name = "player_count", nullable = false)
    private int playerCount = 2;

    @Column(name = "session_id", length = 64)
    private String sessionId;

    @Column(name = "selected_color", nullable = false, length = 8)
    private String selectedColor = "red";

    @Column(name = "game_mode", nullable = false, length = 16)
    private String gameMode = "CLASSIC";

    @Column(name = "queued_at", nullable = false)
    private Instant queuedAt = Instant.now();

    @Column(name = "last_seen_at", nullable = false)
    private Instant lastSeenAt = Instant.now();

    protected MatchmakingTicket() {}

    public MatchmakingTicket(UUID playerId, String displayName, String avatarUrl,
                             String country, String countryFlag, long entryFee,
                             int playerCount, String selectedColor, String sessionId) {
        this(playerId, displayName, avatarUrl, country, countryFlag, entryFee,
                playerCount, selectedColor, sessionId, "CLASSIC");
    }

    public MatchmakingTicket(UUID playerId, String displayName, String avatarUrl,
                             String country, String countryFlag, long entryFee,
                             int playerCount, String selectedColor, String sessionId,
                             String gameMode) {
        this.playerId = playerId;
        this.displayName = displayName;
        this.avatarUrl = avatarUrl;
        this.country = country;
        this.countryFlag = countryFlag;
        this.entryFee = entryFee;
        this.playerCount = playerCount;
        this.selectedColor = selectedColor;
        this.sessionId = sessionId;
        this.gameMode = gameMode;
        this.queuedAt = Instant.now();
        this.lastSeenAt = this.queuedAt;
    }

    public MatchmakingTicket(UUID playerId, String displayName, String avatarUrl,
                             String country, String countryFlag, long entryFee) {
        this(playerId, displayName, avatarUrl, country, countryFlag, entryFee,
                2, "red", null);
    }

    public UUID getPlayerId() { return playerId; }
    public String getDisplayName() { return displayName; }
    public String getAvatarUrl() { return avatarUrl; }
    public String getCountry() { return country; }
    public String getCountryFlag() { return countryFlag; }
    public long getEntryFee() { return entryFee; }
    public int getPlayerCount() { return playerCount; }
    public String getSessionId() { return sessionId; }
    public String getSelectedColor() { return selectedColor; }
    public String getGameMode() { return gameMode; }
    public Instant getQueuedAt() { return queuedAt; }
    public Instant getLastSeenAt() { return lastSeenAt; }
    public void touch() { lastSeenAt = Instant.now(); }
}
