package com.ludoworldfree.backend.model;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "reward_events", uniqueConstraints = {
    @UniqueConstraint(columnNames = {"provider", "providerRewardId"})
})
public class RewardEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;

    @Column(nullable = false)
    private String provider;

    @Column(nullable = false)
    private String providerRewardId;

    @Column(nullable = false)
    private UUID playerId;

    @Column(nullable = false)
    private String rewardType;

    @Column(nullable = false)
    private long amount;

    @Column(nullable = false)
    private String status;

    private Instant processedAt;
    private Instant createdAt;

    public RewardEvent() {}

    public RewardEvent(String provider, String providerRewardId, UUID playerId, String rewardType, long amount, String status) {
        this.provider = provider;
        this.providerRewardId = providerRewardId;
        this.playerId = playerId;
        this.rewardType = rewardType;
        this.amount = amount;
        this.status = status;
        this.processedAt = Instant.now();
        this.createdAt = Instant.now();
    }

    public UUID getId() { return id; }
    public String getProvider() { return provider; }
    public String getProviderRewardId() { return providerRewardId; }
    public UUID getPlayerId() { return playerId; }
    public String getRewardType() { return rewardType; }
    public long getAmount() { return amount; }
    public String getStatus() { return status; }
    public Instant getProcessedAt() { return processedAt; }
    public Instant getCreatedAt() { return createdAt; }
}
