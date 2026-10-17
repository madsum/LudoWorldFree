package com.ludoworldfree.backend.service;

import com.ludoworldfree.backend.dto.DailyRewardClaimResponseDto;
import com.ludoworldfree.backend.dto.DailyRewardStatusDto;
import com.ludoworldfree.backend.model.*;
import com.ludoworldfree.backend.repository.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.*;

@Service
public class DailyRewardService {

    private static final Logger log = LoggerFactory.getLogger(DailyRewardService.class);

    public record RewardDefinition(
            int day,
            String rewardType,
            long amount,
            long diamondBonus,
            String label,
            String description
    ) {}

    private final DailyRewardProgressRepository progressRepository;
    private final PlayerWalletRepository walletRepository;
    private final GoldTransactionRepository transactionRepository;
    private final RewardEventRepository rewardEventRepository;

    public DailyRewardService(
            DailyRewardProgressRepository progressRepository,
            PlayerWalletRepository walletRepository,
            GoldTransactionRepository transactionRepository,
            RewardEventRepository rewardEventRepository) {
        this.progressRepository = progressRepository;
        this.walletRepository = walletRepository;
        this.transactionRepository = transactionRepository;
        this.rewardEventRepository = rewardEventRepository;
    }

    public static RewardDefinition getRewardDefinitionForDay(int day) {
        int cycleDay = ((day - 1) % 28) + 1;
        return switch (cycleDay) {
            case 1 -> new RewardDefinition(1, "COINS", 1000, 0, "1000", "1000 Gold Coins");
            case 2 -> new RewardDefinition(2, "SPIN_TOKENS", 2, 0, "2", "2 Spin Tokens");
            case 3 -> new RewardDefinition(3, "DIAMONDS", 6, 6, "6", "6 Diamonds");
            case 4 -> new RewardDefinition(4, "COINS", 500, 0, "500", "500 Gold Coins");
            case 5 -> new RewardDefinition(5, "DIAMONDS", 8, 8, "8", "8 Diamonds");
            case 6 -> new RewardDefinition(6, "COINS", 600, 0, "600", "600 Gold Coins");
            case 7 -> new RewardDefinition(7, "CHEST", 1000, 10, "BRONZE", "Bronze Chest (1000 Coins + 10 Diamonds)");
            case 14 -> new RewardDefinition(14, "CHEST", 1500, 15, "SILVER", "Silver Chest (1500 Coins + 15 Diamonds)");
            case 21 -> new RewardDefinition(21, "CHEST", 2000, 20, "GOLD", "Gold Chest (2000 Coins + 20 Diamonds)");
            case 28 -> new RewardDefinition(28, "CHEST", 3000, 30, "ROYAL", "Royal Chest (3000 Coins + 30 Diamonds)");
            default -> {
                int modDay = ((cycleDay - 1) % 7) + 1;
                yield switch (modDay) {
                    case 1 -> new RewardDefinition(cycleDay, "COINS", 1000, 0, "1000", "1000 Gold Coins");
                    case 2 -> new RewardDefinition(cycleDay, "SPIN_TOKENS", 2, 0, "2", "2 Spin Tokens");
                    case 3 -> new RewardDefinition(cycleDay, "DIAMONDS", 6, 6, "6", "6 Diamonds");
                    case 4 -> new RewardDefinition(cycleDay, "COINS", 500, 0, "500", "500 Gold Coins");
                    case 5 -> new RewardDefinition(cycleDay, "DIAMONDS", 8, 8, "8", "8 Diamonds");
                    case 6 -> new RewardDefinition(cycleDay, "COINS", 600, 0, "600", "600 Gold Coins");
                    default -> new RewardDefinition(cycleDay, "COINS", 1000, 0, "1000", "1000 Gold Coins");
                };
            }
        };
    }

    @Transactional(readOnly = true)
    public DailyRewardStatusDto getRewardStatus(UUID playerId) {
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        DailyRewardProgress progress = progressRepository.findByPlayerId(playerId)
                .orElseGet(() -> new DailyRewardProgress(playerId));

        boolean canClaimToday;
        int activeStreakDay;

        if (progress.getLastClaimDate() == null) {
            canClaimToday = true;
            activeStreakDay = 1;
        } else if (progress.getLastClaimDate().equals(today)) {
            canClaimToday = false;
            activeStreakDay = progress.getCurrentStreak();
        } else if (progress.getLastClaimDate().equals(today.minusDays(1))) {
            canClaimToday = true;
            activeStreakDay = (progress.getCurrentStreak() % 28) + 1;
        } else {
            // Missed a day or more -> Streak resets to Day 1
            canClaimToday = true;
            activeStreakDay = 1;
        }

        boolean bonusAdClaimedToday = progress.getLastBonusAdClaimDate() != null &&
                progress.getLastBonusAdClaimDate().equals(today);

        Instant nextEligibleClaimTime = today.plusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant();
        long secondsUntilNextClaim = canClaimToday ? 0 :
                Math.max(0, ChronoUnit.SECONDS.between(Instant.now(), nextEligibleClaimTime));

        int pageOffset = ((activeStreakDay - 1) / 7) * 7;
        List<DailyRewardStatusDto.RewardItemDto> rewards = new ArrayList<>();

        for (int index = 1; index <= 7; index++) {
            int displayDay = pageOffset + index;
            RewardDefinition def = getRewardDefinitionForDay(displayDay);

            String status;
            if (displayDay < activeStreakDay || (displayDay == activeStreakDay && !canClaimToday)) {
                status = "CLAIMED";
            } else if (displayDay == activeStreakDay && canClaimToday) {
                status = "CLAIMABLE";
            } else {
                status = "LOCKED";
            }

            rewards.add(new DailyRewardStatusDto.RewardItemDto(
                    displayDay,
                    def.rewardType(),
                    def.amount(),
                    status,
                    def.label(),
                    def.description()
            ));
        }

        List<DailyRewardStatusDto.MilestoneItemDto> milestones = List.of(
                new DailyRewardStatusDto.MilestoneItemDto(7, "BRONZE", progress.getCurrentStreak() >= 7, "7"),
                new DailyRewardStatusDto.MilestoneItemDto(14, "SILVER", progress.getCurrentStreak() >= 14, "14"),
                new DailyRewardStatusDto.MilestoneItemDto(21, "GOLD", progress.getCurrentStreak() >= 21, "21"),
                new DailyRewardStatusDto.MilestoneItemDto(28, "ROYAL", progress.getCurrentStreak() >= 28, "28")
        );

        return new DailyRewardStatusDto(
                progress.getCurrentStreak(),
                activeStreakDay,
                canClaimToday,
                progress.getLastClaimDate(),
                nextEligibleClaimTime,
                secondsUntilNextClaim,
                bonusAdClaimedToday,
                rewards,
                milestones
        );
    }

    @Transactional
    public DailyRewardClaimResponseDto claimDailyReward(UUID playerId) {
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        DailyRewardProgress progress = progressRepository.findByPlayerId(playerId)
                .orElseGet(() -> progressRepository.save(new DailyRewardProgress(playerId)));

        if (progress.getLastClaimDate() != null && progress.getLastClaimDate().equals(today)) {
            log.warn("⚠️ [Duplicate Claim Rejected] Player ID: {} already claimed today on {}", playerId, today);
            PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                    .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));
            return new DailyRewardClaimResponseDto(
                    false,
                    "Reward already claimed for today.",
                    progress.getCurrentStreak(),
                    "NONE",
                    0,
                    wallet.getBalance(),
                    wallet.getDiamonds(),
                    getRewardStatus(playerId)
            );
        }

        int newStreak;
        if (progress.getLastClaimDate() == null || !progress.getLastClaimDate().equals(today.minusDays(1))) {
            newStreak = 1;
        } else {
            newStreak = (progress.getCurrentStreak() % 28) + 1;
        }

        RewardDefinition rewardDef = getRewardDefinitionForDay(newStreak);

        progress.setCurrentStreak(newStreak);
        progress.setLastClaimDate(today);
        progress.setLastClaimTime(Instant.now());
        progressRepository.save(progress);

        PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));

        long balanceBefore = wallet.getBalance();
        long balanceAfter = balanceBefore + (rewardDef.rewardType().equals("DIAMONDS") ? 0 : rewardDef.amount());
        wallet.setBalance(balanceAfter);

        if (rewardDef.diamondBonus() > 0) {
            wallet.setDiamonds(wallet.getDiamonds() + rewardDef.diamondBonus());
        }
        walletRepository.save(wallet);

        GoldTransaction transaction = new GoldTransaction(
                playerId,
                GoldTransaction.TransactionType.DAILY_REWARD,
                rewardDef.amount(),
                balanceBefore,
                balanceAfter,
                "DAILY_REWARD_DAY_" + newStreak,
                "DAILY_BONUS"
        );
        transactionRepository.save(transaction);

        log.info("🎁 [Daily Bonus Claimed] Player ID: {} | Day: {} | Reward: {} ({}) | New Balance: {} Coins, {} Diamonds",
                playerId, newStreak, rewardDef.rewardType(), rewardDef.amount(), balanceAfter, wallet.getDiamonds());

        return new DailyRewardClaimResponseDto(
                true,
                "Successfully claimed Day " + newStreak + " daily bonus!",
                newStreak,
                rewardDef.rewardType(),
                rewardDef.amount(),
                balanceAfter,
                wallet.getDiamonds(),
                getRewardStatus(playerId)
        );
    }

    @Transactional
    public DailyRewardClaimResponseDto claimBonusAdReward(UUID playerId, String providerRewardId) {
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        DailyRewardProgress progress = progressRepository.findByPlayerId(playerId)
                .orElseGet(() -> progressRepository.save(new DailyRewardProgress(playerId)));

        if (progress.getLastBonusAdClaimDate() != null && progress.getLastBonusAdClaimDate().equals(today)) {
            log.warn("⚠️ [Duplicate Bonus Ad Claim] Player ID: {} already claimed bonus ad today", playerId);
            PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                    .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));
            return new DailyRewardClaimResponseDto(
                    false,
                    "Extra bonus ad reward already claimed for today.",
                    progress.getCurrentStreak(),
                    "BONUS_AD",
                    0,
                    wallet.getBalance(),
                    wallet.getDiamonds(),
                    getRewardStatus(playerId)
            );
        }

        Optional<RewardEvent> existingEvent = rewardEventRepository.findByProviderAndProviderRewardId("ADMOB_DAILY_BONUS", providerRewardId);
        PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));

        if (existingEvent.isPresent()) {
            return new DailyRewardClaimResponseDto(
                    false,
                    "Ad reward event already processed.",
                    progress.getCurrentStreak(),
                    "BONUS_AD",
                    0,
                    wallet.getBalance(),
                    wallet.getDiamonds(),
                    getRewardStatus(playerId)
            );
        }

        long rewardAmount = 300L;
        long balanceBefore = wallet.getBalance();
        long balanceAfter = balanceBefore + rewardAmount;
        wallet.setBalance(balanceAfter);

        progress.setBonusAdClaimedToday(true);
        progress.setLastBonusAdClaimDate(today);
        progressRepository.save(progress);

        GoldTransaction transaction = new GoldTransaction(
                playerId,
                GoldTransaction.TransactionType.AD_REWARD,
                rewardAmount,
                balanceBefore,
                balanceAfter,
                providerRewardId,
                "DAILY_BONUS_EXTRA_AD"
        );
        transactionRepository.save(transaction);

        RewardEvent rewardEvent = new RewardEvent(
                "ADMOB_DAILY_BONUS",
                providerRewardId,
                playerId,
                "DAILY_BONUS_EXTRA_AD",
                rewardAmount,
                "PROCESSED"
        );
        rewardEventRepository.save(rewardEvent);

        log.info("🎬 [Extra Ad Bonus Claimed] Player ID: {} | +{} Coins | New Balance: {}",
                playerId, rewardAmount, balanceAfter);

        return new DailyRewardClaimResponseDto(
                true,
                "Extra +300 Gold Coins claimed from video ad!",
                progress.getCurrentStreak(),
                "BONUS_AD",
                rewardAmount,
                balanceAfter,
                wallet.getDiamonds(),
                getRewardStatus(playerId)
        );
    }
}
