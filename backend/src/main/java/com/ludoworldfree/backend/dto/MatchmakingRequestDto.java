package com.ludoworldfree.backend.dto;

import java.util.UUID;

public class MatchmakingRequestDto {
    private UUID playerId;
    private String displayName;
    private String avatarUrl;
    private String country;
    private String countryFlag;
    private long entryFee = 500L;
    private int playerCount = 2;
    private String selectedColor = "red";
    private String sessionId;
    private String gameMode = "CLASSIC";

    public MatchmakingRequestDto() {}

    public MatchmakingRequestDto(UUID playerId, String displayName, String avatarUrl, String country, String countryFlag, long entryFee) {
        this.playerId = playerId;
        this.displayName = displayName;
        this.avatarUrl = avatarUrl;
        this.country = country;
        this.countryFlag = countryFlag;
        this.entryFee = entryFee;
    }

    public UUID getPlayerId() { return playerId; }
    public void setPlayerId(UUID playerId) { this.playerId = playerId; }
    public String getDisplayName() { return displayName; }
    public void setDisplayName(String displayName) { this.displayName = displayName; }
    public String getAvatarUrl() { return avatarUrl; }
    public void setAvatarUrl(String avatarUrl) { this.avatarUrl = avatarUrl; }
    public String getCountry() { return country; }
    public void setCountry(String country) { this.country = country; }
    public String getCountryFlag() { return countryFlag; }
    public void setCountryFlag(String countryFlag) { this.countryFlag = countryFlag; }
    public long getEntryFee() { return entryFee; }
    public void setEntryFee(long entryFee) { this.entryFee = entryFee; }
    public int getPlayerCount() { return playerCount; }
    public void setPlayerCount(int playerCount) { this.playerCount = playerCount; }
    public String getSelectedColor() { return selectedColor; }
    public void setSelectedColor(String selectedColor) { this.selectedColor = selectedColor; }
    public String getSessionId() { return sessionId; }
    public void setSessionId(String sessionId) { this.sessionId = sessionId; }
    public String getGameMode() { return gameMode; }
    public void setGameMode(String gameMode) { this.gameMode = gameMode; }
}
