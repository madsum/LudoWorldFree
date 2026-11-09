package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.repository.LeaderboardEntryProjection;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/leaderboard")
public class LeaderboardController {
    private static final int DEFAULT_LIMIT = 50;
    private static final int MAX_LIMIT = 100;

    private final PlayerProfileRepository profileRepository;

    public LeaderboardController(PlayerProfileRepository profileRepository) {
        this.profileRepository = profileRepository;
    }

    @GetMapping
    public Map<String, Object> getLeaderboard(
            @RequestParam(defaultValue = "50") int limit) {
        int safeLimit = Math.max(1, Math.min(limit, MAX_LIMIT));
        List<LeaderboardEntryProjection> rows = profileRepository.findLeaderboard(safeLimit);
        List<Map<String, Object>> entries = new java.util.ArrayList<>(rows.size());
        for (int index = 0; index < rows.size(); index++) {
            entries.add(toEntry(rows.get(index), index));
        }
        return Map.of("entries", entries);
    }

    private static Map<String, Object> toEntry(LeaderboardEntryProjection entry, int index) {
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("rank", index + 1);
        item.put("playerId", entry.getPlayerId());
        item.put("displayName", entry.getDisplayName());
        item.put("avatarUrl", entry.getAvatarUrl());
        item.put("countryFlag", entry.getCountryFlag());
        item.put("goldCoins", entry.getGoldCoins());
        item.put("gamesPlayed", entry.getGamesPlayed());
        return item;
    }
}
