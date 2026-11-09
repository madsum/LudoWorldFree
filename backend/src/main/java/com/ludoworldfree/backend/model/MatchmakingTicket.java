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

    @Column(name = "queued_at", nullable = false)
    private Instant queuedAt = Instant.now();

    protected MatchmakingTicket() {}

    public MatchmakingTicket(UUID playerId, String displayName, String avatarUrl,
                             String country, String countryFlag, long entryFee) {
        this.playerId = playerId;
        this.displayName = displayName;
        this.avatarUrl = avatarUrl;
        this.country = country;
        this.countryFlag = countryFlag;
        this.entryFee = entryFee;
    }

    public UUID getPlayerId() { return playerId; }
    public String getDisplayName() { return displayName; }
    public String getAvatarUrl() { return avatarUrl; }
    public String getCountry() { return country; }
    public String getCountryFlag() { return countryFlag; }
    public long getEntryFee() { return entryFee; }
    public Instant getQueuedAt() { return queuedAt; }
}
