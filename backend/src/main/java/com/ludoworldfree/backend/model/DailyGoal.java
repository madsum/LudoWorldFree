package com.ludoworldfree.backend.model;

import jakarta.persistence.*;

import java.time.LocalDate;
import java.util.UUID;

@Entity
@Table(name = "daily_goals", uniqueConstraints =
        @UniqueConstraint(name = "uk_daily_goal_player_date_type",
                columnNames = {"player_id", "goal_date", "goal_type"}))
public class DailyGoal {
    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;

    @Column(name = "player_id", nullable = false)
    private UUID playerId;

    @Column(name = "goal_date", nullable = false)
    private LocalDate goalDate;

    @Column(name = "goal_type", nullable = false, length = 40)
    private String goalType;

    @Column(nullable = false)
    private int progress;

    @Column(nullable = false)
    private int target;

    @Column(name = "reward_amount", nullable = false)
    private long rewardAmount;

    @Column(nullable = false)
    private boolean claimed;

    protected DailyGoal() {}

    public DailyGoal(UUID playerId, LocalDate goalDate, String goalType,
                     int target, long rewardAmount) {
        this.playerId = playerId;
        this.goalDate = goalDate;
        this.goalType = goalType;
        this.target = target;
        this.rewardAmount = rewardAmount;
    }

    public UUID getId() { return id; }
    public UUID getPlayerId() { return playerId; }
    public LocalDate getGoalDate() { return goalDate; }
    public String getGoalType() { return goalType; }
    public int getProgress() { return progress; }
    public int getTarget() { return target; }
    public long getRewardAmount() { return rewardAmount; }
    public boolean isClaimed() { return claimed; }
    public void addProgress() { progress = Math.min(target, progress + 1); }
    public void claim() { claimed = true; }
}
