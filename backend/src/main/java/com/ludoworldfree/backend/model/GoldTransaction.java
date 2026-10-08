package com.ludoworldfree.backend.model;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "gold_transactions")
public class GoldTransaction {

    public enum TransactionType {
        AD_REWARD,
        GAME_REWARD,
        DAILY_REWARD,
        BONUS,
        PURCHASE,
        SPEND,
        ADMIN_ADJUSTMENT,
        REFUND
    }

    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;

    @Column(nullable = false)
    private UUID playerId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private TransactionType transactionType;

    @Column(nullable = false)
    private long amount;

    @Column(nullable = false)
    private long balanceBefore;

    @Column(nullable = false)
    private long balanceAfter;

    private String referenceId;
    private String source;

    private Instant createdAt;

    public GoldTransaction() {}

    public GoldTransaction(UUID playerId, TransactionType transactionType, long amount, long balanceBefore, long balanceAfter, String referenceId, String source) {
        this.playerId = playerId;
        this.transactionType = transactionType;
        this.amount = amount;
        this.balanceBefore = balanceBefore;
        this.balanceAfter = balanceAfter;
        this.referenceId = referenceId;
        this.source = source;
        this.createdAt = Instant.now();
    }

    public UUID getId() { return id; }
    public UUID getPlayerId() { return playerId; }
    public TransactionType getTransactionType() { return transactionType; }
    public long getAmount() { return amount; }
    public long getBalanceBefore() { return balanceBefore; }
    public long getBalanceAfter() { return balanceAfter; }
    public String getReferenceId() { return referenceId; }
    public String getSource() { return source; }
    public Instant getCreatedAt() { return createdAt; }
}
