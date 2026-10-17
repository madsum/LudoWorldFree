package com.ludoworldfree.backend.model;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "player_wallets")
public class PlayerWallet {

    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;

    @Column(nullable = false, unique = true)
    private UUID playerId;

    @Column(nullable = false)
    private long balance;

    @Column(nullable = false)
    private long diamonds = 100;

    @Version
    private Long version;

    private Instant createdAt;
    private Instant updatedAt;

    public PlayerWallet() {}

    public PlayerWallet(UUID playerId, long initialBalance) {
        this.playerId = playerId;
        this.balance = initialBalance;
        this.diamonds = 100;
        this.createdAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public UUID getId() { return id; }
    public UUID getPlayerId() { return playerId; }
    public long getBalance() { return balance; }
    public void setBalance(long balance) { this.balance = balance; }
    public long getDiamonds() { return diamonds; }
    public void setDiamonds(long diamonds) { this.diamonds = diamonds; }
    public Long getVersion() { return version; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }

    @PreUpdate
    public void onUpdate() {
        this.updatedAt = Instant.now();
    }
}
