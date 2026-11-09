package com.ludoworldfree.backend.repository;

public interface LeaderboardEntryProjection {
    String getPlayerId();
    String getDisplayName();
    String getAvatarUrl();
    String getCountryFlag();
    long getGoldCoins();
    long getGamesPlayed();
}
