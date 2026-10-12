package com.ludoworldfree.backend.dto;

import java.util.UUID;

public class MatchmakingResponseDto {
    private boolean matchFound;
    private String roomId;
    private UUID opponentId;
    private String opponentName;
    private String opponentAvatarUrl;
    private String opponentCountry;
    private String opponentCountryFlag;
    private String message;

    public MatchmakingResponseDto() {}

    public MatchmakingResponseDto(boolean matchFound, String roomId, UUID opponentId, String opponentName, String opponentAvatarUrl, String opponentCountry, String opponentCountryFlag, String message) {
        this.matchFound = matchFound;
        this.roomId = roomId;
        this.opponentId = opponentId;
        this.opponentName = opponentName;
        this.opponentAvatarUrl = opponentAvatarUrl;
        this.opponentCountry = opponentCountry;
        this.opponentCountryFlag = opponentCountryFlag;
        this.message = message;
    }

    public boolean isMatchFound() { return matchFound; }
    public void setMatchFound(boolean matchFound) { this.matchFound = matchFound; }
    public String getRoomId() { return roomId; }
    public void setRoomId(String roomId) { this.roomId = roomId; }
    public UUID getOpponentId() { return opponentId; }
    public void setOpponentId(UUID opponentId) { this.opponentId = opponentId; }
    public String getOpponentName() { return opponentName; }
    public void setOpponentName(String opponentName) { this.opponentName = opponentName; }
    public String getOpponentAvatarUrl() { return opponentAvatarUrl; }
    public void setOpponentAvatarUrl(String opponentAvatarUrl) { this.opponentAvatarUrl = opponentAvatarUrl; }
    public String getOpponentCountry() { return opponentCountry; }
    public void setOpponentCountry(String opponentCountry) { this.opponentCountry = opponentCountry; }
    public String getOpponentCountryFlag() { return opponentCountryFlag; }
    public void setOpponentCountryFlag(String opponentCountryFlag) { this.opponentCountryFlag = opponentCountryFlag; }
    public String getMessage() { return message; }
    public void setMessage(String message) { this.message = message; }
}
