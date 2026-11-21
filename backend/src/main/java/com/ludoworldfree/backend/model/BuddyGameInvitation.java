package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "buddy_game_invites")
public class BuddyGameInvitation {
    public enum Status { PENDING, ACCEPTED, DECLINED, EXPIRED, CANCELLED }

    @Id
    private UUID id = UUID.randomUUID();

    @Column(name = "requester_id", nullable = false)
    private UUID requesterId;
    @Column(name = "target_id", nullable = false)
    private UUID targetId;
    @Column(name = "entry_fee", nullable = false)
    private long entryFee;
    @Column(name = "requester_session_id", nullable = false, length = 64)
    private String requesterSessionId;
    @Column(name = "requester_color", nullable = false, length = 8)
    private String requesterColor;
    @Column(name = "target_session_id", length = 64)
    private String targetSessionId;
    @Column(name = "target_color", length = 8)
    private String targetColor;
    @Column(name = "room_id", length = 64)
    private String roomId;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private Status status = Status.PENDING;
    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;
    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected BuddyGameInvitation() {}

    public BuddyGameInvitation(UUID requesterId, UUID targetId, long entryFee,
                               String requesterSessionId, String requesterColor) {
        this.requesterId = requesterId;
        this.targetId = targetId;
        this.entryFee = entryFee;
        this.requesterSessionId = requesterSessionId;
        this.requesterColor = requesterColor;
        this.createdAt = Instant.now();
        this.expiresAt = this.createdAt.plusSeconds(60);
    }

    public void accept(String targetSessionId, String targetColor, String roomId) {
        this.targetSessionId = targetSessionId;
        this.targetColor = targetColor;
        this.roomId = roomId;
        this.status = Status.ACCEPTED;
    }

    public void decline() { this.status = Status.DECLINED; }
    public void expire() { this.status = Status.EXPIRED; }
    public void cancel() { this.status = Status.CANCELLED; }

    public UUID getId() { return id; }
    public UUID getRequesterId() { return requesterId; }
    public UUID getTargetId() { return targetId; }
    public long getEntryFee() { return entryFee; }
    public String getRequesterSessionId() { return requesterSessionId; }
    public String getRequesterColor() { return requesterColor; }
    public String getTargetSessionId() { return targetSessionId; }
    public String getTargetColor() { return targetColor; }
    public String getRoomId() { return roomId; }
    public Status getStatus() { return status; }
    public Instant getExpiresAt() { return expiresAt; }
    public Instant getCreatedAt() { return createdAt; }
}
