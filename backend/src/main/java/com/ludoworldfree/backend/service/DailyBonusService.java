package com.ludoworldfree.backend.service;

import com.ludoworldfree.backend.model.GoldTransaction;
import com.ludoworldfree.backend.model.PlayerWallet;
import com.ludoworldfree.backend.repository.GoldTransactionRepository;
import com.ludoworldfree.backend.repository.PlayerWalletRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.UUID;

@Service
public class DailyBonusService {
    private static final long[] REWARDS = {1000, 2000, 4000, 8000, 16000, 32000, 64000};

    private final PlayerWalletRepository walletRepository;
    private final GoldTransactionRepository transactionRepository;

    public DailyBonusService(PlayerWalletRepository walletRepository,
                             GoldTransactionRepository transactionRepository) {
        this.walletRepository = walletRepository;
        this.transactionRepository = transactionRepository;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> status(UUID playerId) {
        PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                .orElseGet(() -> new PlayerWallet(playerId, 2000L));
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        boolean claimedToday = today.equals(wallet.getDailyBonusClaimDate());
        int streak = streakForToday(wallet, today);
        int nextStreak = claimedToday ? streak : streak + 1;
        int rewardDay = ((nextStreak - 1) % REWARDS.length) + 1;
        boolean doubledToday = today.equals(wallet.getDailyBonusDoubleDate());
        return Map.of(
                "claimedToday", claimedToday,
                "doubledToday", doubledToday,
                "doubleRewardAmount", doubledToday ? rewardForDay(rewardDay) : 0,
                "streak", streak,
                "rewardDay", Math.min(rewardDay, REWARDS.length),
                "rewardAmount", claimedToday ? 0 : rewardForDay(rewardDay),
                "balance", wallet.getBalance());
    }

    @Transactional
    public Map<String, Object> claim(UUID playerId) {
        PlayerWallet wallet = walletRepository.findByPlayerIdForUpdate(playerId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        if (today.equals(wallet.getDailyBonusClaimDate())) {
            int rewardDay = ((wallet.getDailyBonusStreak() - 1) % REWARDS.length) + 1;
            return Map.of("success", false, "claimedToday", true,
                    "doubledToday", today.equals(wallet.getDailyBonusDoubleDate()),
                    "streak", wallet.getDailyBonusStreak(), "rewardAmount", 0,
                    "rewardDay", rewardDay, "balance", wallet.getBalance());
        }

        int streak = streakForToday(wallet, today) + 1;
        int rewardDay = ((streak - 1) % REWARDS.length) + 1;
        long reward = rewardForDay(rewardDay);
        long before = wallet.getBalance();
        long after = before + reward;
        wallet.setBalance(after);
        wallet.setDailyBonusClaimDate(today);
        wallet.setDailyBonusStreak(streak);
        walletRepository.save(wallet);
        transactionRepository.save(new GoldTransaction(
                playerId, GoldTransaction.TransactionType.DAILY_BONUS,
                reward, before, after, today.toString(), "DAILY_CHECK_IN"));
        return Map.of("success", true, "claimedToday", true, "streak", streak,
                "doubledToday", false, "rewardDay", rewardDay,
                "rewardAmount", reward, "balance", after);
    }

    @Transactional
    public Map<String, Object> doubleClaim(UUID playerId, String providerRewardId) {
        PlayerWallet wallet = walletRepository.findByPlayerIdForUpdate(playerId).orElse(null);
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        if (wallet == null || !today.equals(wallet.getDailyBonusClaimDate())) {
            return Map.of("success", false, "claimedToday", false,
                    "doubledToday", false, "doubleRewardAmount", 0,
                    "streak", 0, "rewardAmount", 0,
                    "rewardDay", 1, "balance", wallet == null ? 0 : wallet.getBalance());
        }

        int streak = wallet.getDailyBonusStreak();
        int rewardDay = ((streak - 1) % REWARDS.length) + 1;
        if (today.equals(wallet.getDailyBonusDoubleDate())) {
            return Map.of("success", false, "claimedToday", true,
                    "doubledToday", true, "doubleRewardAmount", rewardForDay(rewardDay),
                    "streak", streak, "rewardAmount", 0,
                    "rewardDay", rewardDay, "balance", wallet.getBalance());
        }

        long reward = rewardForDay(rewardDay);
        long before = wallet.getBalance();
        long after = before + reward;
        wallet.setBalance(after);
        wallet.setDailyBonusDoubleDate(today);
        walletRepository.save(wallet);
        transactionRepository.save(new GoldTransaction(
                playerId, GoldTransaction.TransactionType.DAILY_BONUS,
                reward, before, after, providerRewardId, "DAILY_BONUS_DOUBLE_AD"));
        return Map.of("success", true, "claimedToday", true,
                "doubledToday", true, "doubleRewardAmount", reward,
                "streak", streak, "rewardDay", rewardDay,
                "rewardAmount", reward, "balance", after);
    }

    private static int streakForToday(PlayerWallet wallet, LocalDate today) {
        LocalDate previousClaim = wallet.getDailyBonusClaimDate();
        if (previousClaim == null || previousClaim.plusDays(1).isBefore(today)) return 0;
        return wallet.getDailyBonusStreak();
    }

    private static long rewardForDay(int day) {
        return REWARDS[Math.max(1, Math.min(day, REWARDS.length)) - 1];
    }
}
