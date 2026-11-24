package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.Instant;
import java.util.List;
import java.util.Map;
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
    @Column(name = "read_at")
    private Instant readAt;
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "attachments", nullable = false, columnDefinition = "jsonb")
    private List<Map<String, Object>> attachments = List.of();

    protected ChatMessage() {}

    public ChatMessage(UUID senderId, UUID recipientId, String content) {
        this.senderId = senderId;
        this.recipientId = recipientId;
        this.content = content;
    }

    public ChatMessage(UUID senderId, UUID recipientId, String content,
                       List<Map<String, Object>> attachments) {
        this(senderId, recipientId, content);
        this.attachments = attachments == null ? List.of() : List.copyOf(attachments);
    }

    public UUID getId() { return id; }
    public UUID getSenderId() { return senderId; }
    public UUID getRecipientId() { return recipientId; }
    public String getContent() { return content; }
    public MessageType getMessageType() { return messageType; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getReadAt() { return readAt; }
    public List<Map<String, Object>> getAttachments() { return attachments; }
    public void setAttachments(List<Map<String, Object>> attachments) {
        this.attachments = attachments == null ? List.of() : List.copyOf(attachments);
    }
}
