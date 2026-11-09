package com.ludoworldfree.backend.service;

import com.ludoworldfree.backend.model.DailyGoal;
import com.ludoworldfree.backend.model.DailyGoalEvent;
import com.ludoworldfree.backend.model.GoldTransaction;
import com.ludoworldfree.backend.model.PlayerWallet;
import com.ludoworldfree.backend.repository.DailyGoalEventRepository;
import com.ludoworldfree.backend.repository.DailyGoalRepository;
import com.ludoworldfree.backend.repository.GoldTransactionRepository;
import com.ludoworldfree.backend.repository.PlayerWalletRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class DailyGoalService {
    private record GoalDefinition(String type, String title, String description,
                                  int target, long reward) {}

    private static final List<GoalDefinition> DEFINITIONS = List.of(
            new GoalDefinition("PLAY_GAMES", "Play 2 games", "Complete any two games today.", 2, 250),
            new GoalDefinition("WIN_GAME", "Win a game", "Finish first in a game today.", 1, 400),
            new GoalDefinition("ONLINE_GAME", "Play online", "Complete an online game today.", 1, 500));

    private final DailyGoalRepository goalRepository;
    private final DailyGoalEventRepository eventRepository;
    private final PlayerWalletRepository walletRepository;
    private final GoldTransactionRepository transactionRepository;

    public DailyGoalService(DailyGoalRepository goalRepository,
                            DailyGoalEventRepository eventRepository,
                            PlayerWalletRepository walletRepository,
                            GoldTransactionRepository transactionRepository) {
        this.goalRepository = goalRepository;
        this.eventRepository = eventRepository;
        this.walletRepository = walletRepository;
        this.transactionRepository = transactionRepository;
    }

    @Transactional
    public Map<String, Object> getGoals(UUID playerId) {
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        List<DailyGoal> goals = ensureGoals(playerId, today);
        return response(playerId, today, goals);
    }

    @Transactional
    public Map<String, Object> recordEvent(UUID playerId, String eventId,
                                           String eventType, String gameId) {
        if (eventId == null || eventId.isBlank() || eventId.length() > 160
                || gameId == null || gameId.isBlank() || gameId.length() > 100) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "eventId and gameId are required.");
        }
        String type = eventType == null ? "" : eventType.toUpperCase();
        if (!List.of("GAME_COMPLETED", "GAME_WON", "ONLINE_GAME_COMPLETED").contains(type)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unsupported daily goal event.");
        }
        if (eventRepository.existsByPlayerIdAndEventId(playerId, eventId)) {
            return getGoals(playerId);
        }

        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        List<DailyGoal> goals = ensureGoals(playerId, today);
        eventRepository.save(new DailyGoalEvent(playerId, eventId, type, gameId));
        switch (type) {
            case "GAME_COMPLETED" -> increment(goals, "PLAY_GAMES");
            case "GAME_WON" -> increment(goals, "WIN_GAME");
            case "ONLINE_GAME_COMPLETED" -> {
                increment(goals, "PLAY_GAMES");
                increment(goals, "ONLINE_GAME");
            }
            default -> throw new IllegalStateException("Validated event type was not handled.");
        }
        goalRepository.saveAll(goals);
        return response(playerId, today, goals);
    }

    @Transactional
    public Map<String, Object> claim(UUID playerId, String goalType) {
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        ensureGoals(playerId, today);
        String type = goalType == null ? "" : goalType.toUpperCase();
        DailyGoal goal = goalRepository.findForUpdate(playerId, today, type)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Daily goal not found."));
        if (goal.isClaimed()) {
            PlayerWallet currentWallet = walletRepository.findByPlayerId(playerId)
                    .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));
            return Map.of("success", false, "claimed", true,
                    "balance", currentWallet.getBalance(), "rewardAmount", 0);
        }
        if (goal.getProgress() < goal.getTarget()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Complete the goal before claiming its reward.");
        }

        PlayerWallet wallet = walletRepository.findByPlayerIdForUpdate(playerId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));
        long before = wallet.getBalance();
        long after = before + goal.getRewardAmount();
        wallet.setBalance(after);
        goal.claim();
        walletRepository.save(wallet);
        goalRepository.save(goal);
        transactionRepository.save(new GoldTransaction(
                playerId, GoldTransaction.TransactionType.GAME_REWARD,
                goal.getRewardAmount(), before, after,
                today + ":" + goal.getGoalType(), "DAILY_GOAL"));
        return Map.of("success", true, "claimed", true,
                "balance", after, "rewardAmount", goal.getRewardAmount());
    }

    private List<DailyGoal> ensureGoals(UUID playerId, LocalDate date) {
        List<DailyGoal> goals = goalRepository.findAllByPlayerIdAndGoalDateOrderByGoalType(playerId, date);
        if (goals.size() == DEFINITIONS.size()) return goals;
        Map<String, DailyGoal> byType = new LinkedHashMap<>();
        for (DailyGoal goal : goals) byType.put(goal.getGoalType(), goal);
        for (GoalDefinition definition : DEFINITIONS) {
            byType.computeIfAbsent(definition.type(), key ->
                    goalRepository.save(new DailyGoal(playerId, date, key,
                            definition.target(), definition.reward())));
        }
        return new ArrayList<>(byType.values());
    }

    private void increment(List<DailyGoal> goals, String type) {
        goals.stream().filter(goal -> goal.getGoalType().equals(type))
                .findFirst().ifPresent(DailyGoal::addProgress);
    }

    private Map<String, Object> response(UUID playerId, LocalDate date,
                                         List<DailyGoal> goals) {
        PlayerWallet wallet = walletRepository.findByPlayerId(playerId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2000L)));
        List<Map<String, Object>> entries = new ArrayList<>();
        for (DailyGoal goal : goals) {
            GoalDefinition definition = DEFINITIONS.stream()
                    .filter(candidate -> candidate.type().equals(goal.getGoalType()))
                    .findFirst().orElseThrow();
            Map<String, Object> entry = new LinkedHashMap<>();
            entry.put("type", goal.getGoalType());
            entry.put("title", definition.title());
            entry.put("description", definition.description());
            entry.put("progress", goal.getProgress());
            entry.put("target", goal.getTarget());
            entry.put("rewardAmount", goal.getRewardAmount());
            entry.put("claimed", goal.isClaimed());
            entry.put("claimable", !goal.isClaimed() && goal.getProgress() >= goal.getTarget());
            entries.add(entry);
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("date", date.toString());
        result.put("entries", entries);
        result.put("balance", wallet.getBalance());
        return result;
    }
}
