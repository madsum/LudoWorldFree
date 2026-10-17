package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.dto.DailyRewardClaimResponseDto;
import com.ludoworldfree.backend.dto.DailyRewardStatusDto;
import com.ludoworldfree.backend.service.DailyRewardService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/daily-rewards")
public class DailyRewardController {

    private final DailyRewardService dailyRewardService;

    public DailyRewardController(DailyRewardService dailyRewardService) {
        this.dailyRewardService = dailyRewardService;
    }

    @GetMapping
    public ResponseEntity<DailyRewardStatusDto> getRewardStatus(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        DailyRewardStatusDto status = dailyRewardService.getRewardStatus(playerId);
        return ResponseEntity.ok(status);
    }

    @PostMapping("/claim")
    public ResponseEntity<DailyRewardClaimResponseDto> claimDailyReward(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        DailyRewardClaimResponseDto response = dailyRewardService.claimDailyReward(playerId);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/bonus-ad/claim")
    public ResponseEntity<DailyRewardClaimResponseDto> claimBonusAdReward(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestBody Map<String, Object> payload) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        String providerRewardId = (String) payload.get("providerRewardId");
        if (providerRewardId == null || providerRewardId.isBlank()) {
            providerRewardId = "bonus_ad_" + UUID.randomUUID();
        }

        DailyRewardClaimResponseDto response = dailyRewardService.claimBonusAdReward(playerId, providerRewardId);
        return ResponseEntity.ok(response);
    }
}
