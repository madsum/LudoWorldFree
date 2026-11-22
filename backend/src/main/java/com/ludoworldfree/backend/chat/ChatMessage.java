package com.ludoworldfree.backend.chat;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

public record ChatMessage(
        UUID id,
        UUID conversationId,
        long sequence,
        UUID senderId,
        UUID clientMessageId,
        String body,
        String ciphertext,
        boolean encrypted,
        String contentType,
        List<Map<String, Object>> attachments,
        Long replyToSequence,
        Instant createdAt) {
    public Map<String, Object> toMap() {
        return Map.ofEntries(
                Map.entry("id", id.toString()),
                Map.entry("conversationId", conversationId.toString()),
                Map.entry("sequence", sequence),
                Map.entry("senderId", senderId.toString()),
                Map.entry("clientMessageId", clientMessageId.toString()),
                Map.entry("body", body == null ? "" : body),
                Map.entry("ciphertext", ciphertext == null ? "" : ciphertext),
                Map.entry("encrypted", encrypted),
                Map.entry("contentType", contentType),
                Map.entry("attachments", attachments),
                Map.entry("replyToSequence", replyToSequence == null ? 0L : replyToSequence),
                Map.entry("createdAt", createdAt.toString()));
    }
}
