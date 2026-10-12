package com.ludoworldfree.backend.model;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "player_profiles")
public class PlayerProfile {

    public enum GameType {
        CLASSIC,
        QUICK,
        TEAM_UP,
        COMPUTER,
        PASS_N_PLAY
    }

    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;

    @Column(nullable = false, unique = true)
    private UUID userId;

    @Column(nullable = false)
    private String displayName;

    private String avatarUrl;
    private String country;
    private String countryFlag;

    @Enumerated(EnumType.STRING)
    private GameType preferredGameType = GameType.CLASSIC;

    @Enumerated(EnumType.STRING)
    private GameType mostPlayedGameType = GameType.CLASSIC;

    private int classicPlayCount = 0;
    private int quickPlayCount = 0;
    private int teamUpPlayCount = 0;
    private int computerPlayCount = 0;
    private int passNPlayPlayCount = 0;

    private Instant createdAt;
    private Instant updatedAt;

    public PlayerProfile() {}

    public PlayerProfile(UUID userId, String displayName, String avatarUrl, String country, String countryFlag) {
        this.userId = userId;
        this.displayName = displayName;
        this.avatarUrl = avatarUrl;
        this.country = country;
        this.countryFlag = countryFlag;
        this.preferredGameType = GameType.CLASSIC;
        this.mostPlayedGameType = GameType.CLASSIC;
        this.createdAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public void recordGameSession(GameType type) {
        if (type == null) return;
        switch (type) {
            case CLASSIC -> this.classicPlayCount++;
            case QUICK -> this.quickPlayCount++;
            case TEAM_UP -> this.teamUpPlayCount++;
            case COMPUTER -> this.computerPlayCount++;
            case PASS_N_PLAY -> this.passNPlayPlayCount++;
        }
        recalculateMostPlayedGameType();
    }

    public void recalculateMostPlayedGameType() {
        GameType highest = GameType.CLASSIC;
        int maxCount = this.classicPlayCount;

        if (this.quickPlayCount > maxCount) {
            maxCount = this.quickPlayCount;
            highest = GameType.QUICK;
        }
        if (this.teamUpPlayCount > maxCount) {
            maxCount = this.teamUpPlayCount;
            highest = GameType.TEAM_UP;
        }
        if (this.computerPlayCount > maxCount) {
            maxCount = this.computerPlayCount;
            highest = GameType.COMPUTER;
        }
        if (this.passNPlayPlayCount > maxCount) {
            highest = GameType.PASS_N_PLAY;
        }

        this.mostPlayedGameType = highest;
    }

    public UUID getId() { return id; }
    public UUID getUserId() { return userId; }
    public String getDisplayName() { return displayName; }
    public void setDisplayName(String displayName) { this.displayName = displayName; }
    public String getAvatarUrl() { return avatarUrl; }
    public void setAvatarUrl(String avatarUrl) { this.avatarUrl = avatarUrl; }
    public String getCountry() { return country; }
    public void setCountry(String country) { this.country = country; }
    public String getCountryFlag() { return countryFlag; }
    public void setCountryFlag(String countryFlag) { this.countryFlag = countryFlag; }
    
    public GameType getPreferredGameType() { return preferredGameType; }
    public void setPreferredGameType(GameType preferredGameType) { this.preferredGameType = preferredGameType; }
    
    public GameType getMostPlayedGameType() { return mostPlayedGameType; }
    public void setMostPlayedGameType(GameType mostPlayedGameType) { this.mostPlayedGameType = mostPlayedGameType; }
    
    public int getClassicPlayCount() { return classicPlayCount; }
    public int getQuickPlayCount() { return quickPlayCount; }
    public int getTeamUpPlayCount() { return teamUpPlayCount; }
    public int getComputerPlayCount() { return computerPlayCount; }
    public int getPassNPlayPlayCount() { return passNPlayPlayCount; }

    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }

    @PreUpdate
    public void onUpdate() {
        this.updatedAt = Instant.now();
    }
}
