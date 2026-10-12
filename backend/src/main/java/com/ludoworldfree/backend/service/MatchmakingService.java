package com.ludoworldfree.backend.service;

import com.ludoworldfree.backend.dto.MatchmakingRequestDto;
import com.ludoworldfree.backend.dto.MatchmakingResponseDto;
import com.ludoworldfree.backend.model.GoldTransaction;
import com.ludoworldfree.backend.model.PlayerWallet;
import com.ludoworldfree.backend.repository.GoldTransactionRepository;
import com.ludoworldfree.backend.repository.PlayerWalletRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class MatchmakingService {

    private final PlayerWalletRepository walletRepository;
    private final GoldTransactionRepository transactionRepository;

    private final Map<UUID, MatchmakingRequestDto> queue = new ConcurrentHashMap<>();
    private final Map<UUID, MatchmakingResponseDto> matchedResults = new ConcurrentHashMap<>();

    public MatchmakingService(
            PlayerWalletRepository walletRepository,
            GoldTransactionRepository transactionRepository) {
        this.walletRepository = walletRepository;
        this.transactionRepository = transactionRepository;
    }

    @Transactional
    public synchronized MatchmakingResponseDto joinQueue(MatchmakingRequestDto request) {
        UUID playerId = request.getPlayerId();

        // 1. Check if already matched
        if (matchedResults.containsKey(playerId)) {
            return matchedResults.get(playerId);
        }

        // 2. Check and deduct entry fee
        long entryFee = request.getEntryFee();
        PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));

        if (wallet.getBalance() < entryFee) {
            return new MatchmakingResponseDto(false, null, null, null, null, null, null, "Insufficient gold coins for entry fee.");
        }

        // Add to queue
        queue.put(playerId, request);

        // 3. Matchmaking logic: If 2 or more players in queue, match them!
        if (queue.size() >= 2) {
            Iterator<UUID> iterator = queue.keySet().iterator();
            UUID playerAId = iterator.next();
            UUID playerBId = iterator.next();

            MatchmakingRequestDto playerA = queue.remove(playerAId);
            MatchmakingRequestDto playerB = queue.remove(playerBId);

            String roomId = "room_online_" + System.currentTimeMillis() + "_" + (System.nanoTime() % 1000);

            // Deduct entry fees
            deductEntryFee(playerAId, entryFee, roomId);
            deductEntryFee(playerBId, entryFee, roomId);

            // Create match results for both players
            MatchmakingResponseDto resultForA = new MatchmakingResponseDto(
                    true, roomId, playerB.getPlayerId(), playerB.getDisplayName(),
                    playerB.getAvatarUrl(), playerB.getCountry(), playerB.getCountryFlag(), "Match Found!"
            );

            MatchmakingResponseDto resultForB = new MatchmakingResponseDto(
                    true, roomId, playerA.getPlayerId(), playerA.getDisplayName(),
                    playerA.getAvatarUrl(), playerA.getCountry(), playerA.getCountryFlag(), "Match Found!"
            );

            matchedResults.put(playerAId, resultForA);
            matchedResults.put(playerBId, resultForB);

            return resultForA.getOpponentId().equals(playerBId) ? resultForA : resultForB;
        }

        // Single player in queue: return waiting response
        return new MatchmakingResponseDto(false, null, null, null, null, null, null, "Searching for online players...");
    }

    public synchronized MatchmakingResponseDto checkStatus(UUID playerId) {
        if (matchedResults.containsKey(playerId)) {
            return matchedResults.get(playerId);
        }
        return new MatchmakingResponseDto(false, null, null, null, null, null, null, "Searching for online players...");
    }

    public synchronized void cancelQueue(UUID playerId) {
        queue.remove(playerId);
        matchedResults.remove(playerId);
    }

    private void deductEntryFee(UUID playerId, long entryFee, String roomId) {
        PlayerWallet wallet = walletRepository.findByPlayerId(playerId).orElse(null);
        if (wallet != null && wallet.getBalance() >= entryFee) {
            long before = wallet.getBalance();
            long after = before - entryFee;
            wallet.setBalance(after);
            walletRepository.save(wallet);

            GoldTransaction transaction = new GoldTransaction(
                    playerId,
                    GoldTransaction.TransactionType.SPEND,
                    entryFee,
                    before,
                    after,
                    roomId,
                    "MATCHMAKING_ENTRY_FEE"
            );
            transactionRepository.save(transaction);
        }
    }
}
