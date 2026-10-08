package com.ludoworldfree.backend.service;

import com.ludoworldfree.backend.model.*;
import com.ludoworldfree.backend.repository.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;
import java.util.UUID;

@Service
public class RewardService {

    private final PlayerWalletRepository walletRepository;
    private final GoldTransactionRepository transactionRepository;
    private final RewardEventRepository rewardEventRepository;

    public RewardService(
            PlayerWalletRepository walletRepository,
            GoldTransactionRepository transactionRepository,
            RewardEventRepository rewardEventRepository) {
        this.walletRepository = walletRepository;
        this.transactionRepository = transactionRepository;
        this.rewardEventRepository = rewardEventRepository;
    }

    @Transactional
    public RewardResult processAdReward(UUID playerId, String providerRewardId, long rewardAmount) {
        // 1. Idempotency Check: Prevent duplicate / replayed reward events
        Optional<RewardEvent> existingEvent = rewardEventRepository.findByProviderAndProviderRewardId("ADMOB", providerRewardId);
        
        PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2350)));

        if (existingEvent.isPresent()) {
            return new RewardResult(true, wallet.getBalance(), "Reward already processed.", true);
        }

        // 2. Atomically update wallet balance
        long balanceBefore = wallet.getBalance();
        long balanceAfter = balanceBefore + rewardAmount;
        wallet.setBalance(balanceAfter);
        walletRepository.save(wallet);

        // 3. Append GoldTransaction log
        GoldTransaction transaction = new GoldTransaction(
                playerId,
                GoldTransaction.TransactionType.AD_REWARD,
                rewardAmount,
                balanceBefore,
                balanceAfter,
                providerRewardId,
                "ADMOB_REWARDED_VIDEO"
        );
        transactionRepository.save(transaction);

        // 4. Save RewardEvent for Idempotency
        RewardEvent rewardEvent = new RewardEvent(
                "ADMOB",
                providerRewardId,
                playerId,
                "AD_REWARD",
                rewardAmount,
                "PROCESSED"
        );
        rewardEventRepository.save(rewardEvent);

        return new RewardResult(true, balanceAfter, "Reward processed successfully.", false);
    }

    public record RewardResult(boolean success, long currentBalance, String message, boolean duplicate) {}
}
