package com.ludoworldfree.backend.service;

import com.ludoworldfree.backend.dto.DailyRewardClaimResponseDto;
import com.ludoworldfree.backend.dto.DailyRewardStatusDto;
import com.ludoworldfree.backend.model.*;
import com.ludoworldfree.backend.repository.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class DailyRewardServiceTest {

    private DailyRewardProgressRepository progressRepository;
    private PlayerWalletRepository walletRepository;
    private GoldTransactionRepository transactionRepository;
    private RewardEventRepository rewardEventRepository;
    private DailyRewardService dailyRewardService;

    private UUID playerId;

    @BeforeEach
    void setUp() {
        progressRepository = mock(DailyRewardProgressRepository.class);
        walletRepository = mock(PlayerWalletRepository.class);
        transactionRepository = mock(GoldTransactionRepository.class);
        rewardEventRepository = mock(RewardEventRepository.class);

        dailyRewardService = new DailyRewardService(
                progressRepository,
                walletRepository,
                transactionRepository,
                rewardEventRepository
        );

        playerId = UUID.randomUUID();
    }

    @Test
    @DisplayName("New player status returns Day 1 claimable")
    void testGetRewardStatus_NewPlayer() {
        when(progressRepository.findByPlayerId(playerId)).thenReturn(Optional.empty());

        DailyRewardStatusDto status = dailyRewardService.getRewardStatus(playerId);

        assertTrue(status.canClaimToday());
        assertEquals(0, status.currentStreak());
        assertEquals(1, status.activeDay());
        assertEquals(7, status.rewards().size());
        assertEquals("CLAIMABLE", status.rewards().get(0).status());
        assertEquals(500, status.rewards().get(0).amount());
    }

    @Test
    @DisplayName("First claim for new player credits Day 1 reward (500 Gold Coins)")
    void testClaimDailyReward_FirstClaim() {
        DailyRewardProgress progress = new DailyRewardProgress(playerId);
        PlayerWallet wallet = new PlayerWallet(playerId, 2000L);

        when(progressRepository.findByPlayerId(playerId)).thenReturn(Optional.of(progress));
        when(walletRepository.findByPlayerId(playerId)).thenReturn(Optional.of(wallet));
        when(progressRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(walletRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        DailyRewardClaimResponseDto response = dailyRewardService.claimDailyReward(playerId);

        assertTrue(response.success());
        assertEquals(1, response.claimedDay());
        assertEquals("COINS", response.rewardType());
        assertEquals(500, response.amount());
        assertEquals(2500, response.currentCoins());
        verify(transactionRepository, times(1)).save(any());
    }

    @Test
    @DisplayName("Duplicate claim on the same day is rejected")
    void testClaimDailyReward_SameDayDuplicateRejected() {
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        DailyRewardProgress progress = new DailyRewardProgress(playerId);
        progress.setCurrentStreak(1);
        progress.setLastClaimDate(today);

        PlayerWallet wallet = new PlayerWallet(playerId, 3000L);

        when(progressRepository.findByPlayerId(playerId)).thenReturn(Optional.of(progress));
        when(walletRepository.findByPlayerId(playerId)).thenReturn(Optional.of(wallet));

        DailyRewardClaimResponseDto response = dailyRewardService.claimDailyReward(playerId);

        assertFalse(response.success());
        assertEquals("Reward already claimed for today.", response.message());
        assertEquals(3000, response.currentCoins());
        verify(walletRepository, never()).save(any());
    }

    @Test
    @DisplayName("Consecutive day claim increments streak to Day 2 (1000 Gold Coins)")
    void testClaimDailyReward_ConsecutiveDay() {
        LocalDate yesterday = LocalDate.now(ZoneOffset.UTC).minusDays(1);
        DailyRewardProgress progress = new DailyRewardProgress(playerId);
        progress.setCurrentStreak(1);
        progress.setLastClaimDate(yesterday);

        PlayerWallet wallet = new PlayerWallet(playerId, 3000L);

        when(progressRepository.findByPlayerId(playerId)).thenReturn(Optional.of(progress));
        when(walletRepository.findByPlayerId(playerId)).thenReturn(Optional.of(wallet));
        when(progressRepository.save(any())).thenAnswer(i -> i.getArgument(0));
        when(walletRepository.save(any())).thenAnswer(i -> i.getArgument(0));

        DailyRewardClaimResponseDto response = dailyRewardService.claimDailyReward(playerId);

        assertTrue(response.success());
        assertEquals(2, response.claimedDay());
        assertEquals("COINS", response.rewardType());
        assertEquals(1000, response.amount());
    }

    @Test
    @DisplayName("Missed day resets streak to Day 1")
    void testClaimDailyReward_MissedDayResetsStreak() {
        LocalDate threeDaysAgo = LocalDate.now(ZoneOffset.UTC).minusDays(3);
        DailyRewardProgress progress = new DailyRewardProgress(playerId);
        progress.setCurrentStreak(5);
        progress.setLastClaimDate(threeDaysAgo);

        PlayerWallet wallet = new PlayerWallet(playerId, 5000L);

        when(progressRepository.findByPlayerId(playerId)).thenReturn(Optional.of(progress));
        when(walletRepository.findByPlayerId(playerId)).thenReturn(Optional.of(wallet));
        when(progressRepository.save(any())).thenAnswer(i -> i.getArgument(0));
        when(walletRepository.save(any())).thenAnswer(i -> i.getArgument(0));

        DailyRewardClaimResponseDto response = dailyRewardService.claimDailyReward(playerId);

        assertTrue(response.success());
        assertEquals(1, response.claimedDay()); // Streak reset to Day 1
        assertEquals(500, response.amount());
        assertEquals(5500, response.currentCoins());
    }

    @Test
    @DisplayName("Day 7 milestone chest grants 1000 Coins + 10 Diamonds")
    void testClaimDailyReward_Day7ChestMilestone() {
        LocalDate yesterday = LocalDate.now(ZoneOffset.UTC).minusDays(1);
        DailyRewardProgress progress = new DailyRewardProgress(playerId);
        progress.setCurrentStreak(6);
        progress.setLastClaimDate(yesterday);

        PlayerWallet wallet = new PlayerWallet(playerId, 4000L);
        wallet.setDiamonds(100);

        when(progressRepository.findByPlayerId(playerId)).thenReturn(Optional.of(progress));
        when(walletRepository.findByPlayerId(playerId)).thenReturn(Optional.of(wallet));
        when(progressRepository.save(any())).thenAnswer(i -> i.getArgument(0));
        when(walletRepository.save(any())).thenAnswer(i -> i.getArgument(0));

        DailyRewardClaimResponseDto response = dailyRewardService.claimDailyReward(playerId);

        assertTrue(response.success());
        assertEquals(7, response.claimedDay());
        assertEquals("CHEST", response.rewardType());
        assertEquals(1000, response.amount());
        assertEquals(5000, response.currentCoins());
        assertEquals(110, response.currentDiamonds()); // +10 Diamonds
    }

    @Test
    @DisplayName("Extra bonus ad claim credits +300 Gold Coins and marks ad claimed today")
    void testClaimBonusAdReward_Success() {
        DailyRewardProgress progress = new DailyRewardProgress(playerId);
        PlayerWallet wallet = new PlayerWallet(playerId, 2000L);
        String rewardId = "ad_reward_12345";

        when(progressRepository.findByPlayerId(playerId)).thenReturn(Optional.of(progress));
        when(walletRepository.findByPlayerId(playerId)).thenReturn(Optional.of(wallet));
        when(rewardEventRepository.findByProviderAndProviderRewardId("ADMOB_DAILY_BONUS", rewardId)).thenReturn(Optional.empty());
        when(progressRepository.save(any())).thenAnswer(i -> i.getArgument(0));
        when(walletRepository.save(any())).thenAnswer(i -> i.getArgument(0));

        DailyRewardClaimResponseDto response = dailyRewardService.claimBonusAdReward(playerId, rewardId);

        assertTrue(response.success());
        assertEquals(300, response.amount());
        assertEquals(2300, response.currentCoins());
        assertTrue(progress.isBonusAdClaimedToday());
        verify(rewardEventRepository, times(1)).save(any());
    }

    @Test
    @DisplayName("Duplicate bonus ad claim rejected on same day")
    void testClaimBonusAdReward_DuplicateRejected() {
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        DailyRewardProgress progress = new DailyRewardProgress(playerId);
        progress.setBonusAdClaimedToday(true);
        progress.setLastBonusAdClaimDate(today);

        PlayerWallet wallet = new PlayerWallet(playerId, 2300L);

        when(progressRepository.findByPlayerId(playerId)).thenReturn(Optional.of(progress));
        when(walletRepository.findByPlayerId(playerId)).thenReturn(Optional.of(wallet));

        DailyRewardClaimResponseDto response = dailyRewardService.claimBonusAdReward(playerId, "ad_reward_dup");

        assertFalse(response.success());
        assertEquals("Extra bonus ad reward already claimed for today.", response.message());
        assertEquals(2300, response.currentCoins());
    }
}
