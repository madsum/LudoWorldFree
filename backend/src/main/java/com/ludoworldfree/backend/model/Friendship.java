package com.ludoworldfree.backend.model;

import jakarta.persistence.*;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "friendships", uniqueConstraints =
        @UniqueConstraint(name = "uk_requester_addressee", columnNames = {"requester_id", "addressee_id"}))
public class Friendship {
    public enum Status { PENDING, ACCEPTED, REJECTED }

    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;

    @Column(name = "requester_id", nullable = false)
    private UUID requesterId;

    @Column(name = "addressee_id", nullable = false)
    private UUID addresseeId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Status status = Status.PENDING;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    protected Friendship() {}

    public Friendship(UUID requesterId, UUID addresseeId) {
        this.requesterId = requesterId;
        this.addresseeId = addresseeId;
    }

    public UUID getId() { return id; }
    public UUID getRequesterId() { return requesterId; }
    public UUID getAddresseeId() { return addresseeId; }
    public Status getStatus() { return status; }
    public Instant getUpdatedAt() { return updatedAt; }

    public void accept() {
        status = Status.ACCEPTED;
        updatedAt = Instant.now();
    }

    public void reject() {
        status = Status.REJECTED;
        updatedAt = Instant.now();
    }

    @PreUpdate
    public void onUpdate() { updatedAt = Instant.now(); }
}
