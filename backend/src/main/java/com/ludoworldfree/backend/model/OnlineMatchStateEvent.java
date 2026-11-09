package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "online_match_state_events")
public class OnlineMatchStateEvent {
    @Id
    private UUID id = UUID.randomUUID();

    @Column(name = "room_id", nullable = false, length = 64)
    private String roomId;

    @Column(nullable = false)
    private long revision;

    @Column(name = "sender_id", nullable = false)
    private UUID senderId;

    @Column(name = "state_json", nullable = false, columnDefinition = "TEXT")
    private String stateJson;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected OnlineMatchStateEvent() {}

    public OnlineMatchStateEvent(String roomId, long revision, UUID senderId, String stateJson) {
        this.roomId = roomId;
        this.revision = revision;
        this.senderId = senderId;
        this.stateJson = stateJson;
    }

    public long getRevision() { return revision; }
    public UUID getSenderId() { return senderId; }
    public String getStateJson() { return stateJson; }
}
