package com.ludoworldfree.backend.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

public record DailyRewardStatusDto(
        int currentStreak,
        int activeDay,
        boolean canClaimToday,
        LocalDate lastClaimDate,
        Instant nextEligibleClaimTime,
        long secondsUntilNextClaim,
        boolean bonusAdClaimedToday,
        List<RewardItemDto> rewards,
        List<MilestoneItemDto> milestones
) {
    public record RewardItemDto(
            int day,
            String rewardType,
            long amount,
            String status,
            String label,
            String description
    ) {}

    public record MilestoneItemDto(
            int day,
            String chestType,
            boolean unlocked,
            String label
    ) {}
}
