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
@Table(name = "chat_messages")
public class ChatMessage {
    public enum MessageType { TEXT }

    @Id
    private UUID id = UUID.randomUUID();

    @Column(name = "sender_id", nullable = false)
    private UUID senderId;

    @Column(name = "recipient_id", nullable = false)
    private UUID recipientId;

    @Column(nullable = false, length = 1000)
    private String content;

    @Enumerated(EnumType.STRING)
    @Column(name = "message_type", nullable = false, length = 16)
    private MessageType messageType = MessageType.TEXT;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected ChatMessage() {}

    public ChatMessage(UUID senderId, UUID recipientId, String content) {
        this.senderId = senderId;
        this.recipientId = recipientId;
        this.content = content;
    }

    public UUID getId() { return id; }
    public UUID getSenderId() { return senderId; }
    public UUID getRecipientId() { return recipientId; }
    public String getContent() { return content; }
    public MessageType getMessageType() { return messageType; }
    public Instant getCreatedAt() { return createdAt; }
}
