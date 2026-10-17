package com.ludoworldfree.backend.dto;

public record DailyRewardClaimResponseDto(
        boolean success,
        String message,
        int claimedDay,
        String rewardType,
        long amount,
        long currentCoins,
        long currentDiamonds,
        DailyRewardStatusDto updatedStatus
) {}
