package com.ludoworldfree.backend.model;

import jakarta.persistence.*;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

@Entity
@Table(name = "daily_reward_progress")
public class DailyRewardProgress {

    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;

    @Column(name = "player_id", nullable = false, unique = true)
    private UUID playerId;

    @Column(name = "current_streak", nullable = false)
    private int currentStreak = 0;

    @Column(name = "last_claim_date")
    private LocalDate lastClaimDate;

    @Column(name = "last_claim_time")
    private Instant lastClaimTime;

    @Column(name = "bonus_ad_claimed_today", nullable = false)
    private boolean bonusAdClaimedToday = false;

    @Column(name = "last_bonus_ad_claim_date")
    private LocalDate lastBonusAdClaimDate;

    @Version
    private Long version;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    public DailyRewardProgress() {}

    public DailyRewardProgress(UUID playerId) {
        this.playerId = playerId;
        this.currentStreak = 0;
        this.createdAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public UUID getPlayerId() {
        return playerId;
    }

    public void setPlayerId(UUID playerId) {
        this.playerId = playerId;
    }

    public int getCurrentStreak() {
        return currentStreak;
    }

    public void setCurrentStreak(int currentStreak) {
        this.currentStreak = currentStreak;
    }

    public LocalDate getLastClaimDate() {
        return lastClaimDate;
    }

    public void setLastClaimDate(LocalDate lastClaimDate) {
        this.lastClaimDate = lastClaimDate;
    }

    public Instant getLastClaimTime() {
        return lastClaimTime;
    }

    public void setLastClaimTime(Instant lastClaimTime) {
        this.lastClaimTime = lastClaimTime;
    }

    public boolean isBonusAdClaimedToday() {
        return bonusAdClaimedToday;
    }

    public void setBonusAdClaimedToday(boolean bonusAdClaimedToday) {
        this.bonusAdClaimedToday = bonusAdClaimedToday;
    }

    public LocalDate getLastBonusAdClaimDate() {
        return lastBonusAdClaimDate;
    }

    public void setLastBonusAdClaimDate(LocalDate lastBonusAdClaimDate) {
        this.lastBonusAdClaimDate = lastBonusAdClaimDate;
    }

    public Long getVersion() {
        return version;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    @PreUpdate
    public void onUpdate() {
        this.updatedAt = Instant.now();
    }
}
