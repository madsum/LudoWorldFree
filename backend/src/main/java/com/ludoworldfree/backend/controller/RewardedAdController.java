package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.service.RewardService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/rewards")
public class RewardedAdController {

    private final RewardService rewardService;

    public RewardedAdController(RewardService rewardService) {
        this.rewardService = rewardService;
    }

    @PostMapping("/ad-reward")
    public ResponseEntity<?> claimAdReward(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestBody Map<String, Object> payload) {

        String providerRewardId = (String) payload.get("providerRewardId");
        if (providerRewardId == null || providerRewardId.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid or missing providerRewardId"));
        }

        UUID playerId;
        try {
            playerId = (headerPlayerId != null && !headerPlayerId.isBlank())
                    ? UUID.fromString(headerPlayerId)
                    : UUID.nameUUIDFromBytes(providerRewardId.getBytes());
        } catch (Exception e) {
            playerId = UUID.randomUUID();
        }

        // Fixed server-side reward amount (never trust client-supplied gold amount)
        long serverRewardAmount = 500L;

        RewardService.RewardResult result = rewardService.processAdReward(playerId, providerRewardId, serverRewardAmount);

        return ResponseEntity.ok(Map.of(
                "success", result.success(),
                "balance", result.currentBalance(),
                "message", result.message(),
                "duplicate", result.duplicate()
        ));
    }
}
