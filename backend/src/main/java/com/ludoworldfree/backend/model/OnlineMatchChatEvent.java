package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "online_match_chat_events")
public class OnlineMatchChatEvent {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "room_id", nullable = false, length = 64)
    private String roomId;

    @Column(name = "player_id", nullable = false)
    private UUID playerId;

    @Column(name = "message_text", nullable = false, length = 200)
    private String text;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected OnlineMatchChatEvent() {}

    public OnlineMatchChatEvent(String roomId, UUID playerId, String text) {
        this.roomId = roomId;
        this.playerId = playerId;
        this.text = text;
    }

    public Long getId() { return id; }
    public String getRoomId() { return roomId; }
    public UUID getPlayerId() { return playerId; }
    public String getText() { return text; }
    public Instant getCreatedAt() { return createdAt; }
}
