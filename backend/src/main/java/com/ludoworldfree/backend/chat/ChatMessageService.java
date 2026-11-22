package com.ludoworldfree.backend.chat;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class ChatMessageService {
    private static final TypeReference<List<Map<String, Object>>> ATTACHMENTS_TYPE =
            new TypeReference<>() {};

    public record SendRequest(UUID clientMessageId, String body, String ciphertext,
                              boolean encrypted, String contentType,
                              List<Map<String, Object>> attachments,
                              Long replyToSequence) {}

    public record MessagePage(List<Map<String, Object>> messages,
                              long lastSequence, boolean hasMore) {}

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final ChatConversationService conversations;
    private final ChatEventPublisher eventPublisher;

    public ChatMessageService(JdbcTemplate jdbc, ObjectMapper objectMapper,
                              ChatConversationService conversations,
                              ChatEventPublisher eventPublisher) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
        this.conversations = conversations;
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public ChatMessage send(UUID senderId, UUID conversationId, SendRequest request) {
        validate(request);
        lockConversation(conversationId, senderId);
        ChatMessage duplicate = findByClientId(conversationId, senderId,
                request.clientMessageId());
        if (duplicate != null) return duplicate;

        if (request.replyToSequence() != null) {
            Integer exists = jdbc.queryForObject("""
                    SELECT COUNT(*) FROM messages
                    WHERE conversation_id = ? AND sequence = ?
                    """, Integer.class, conversationId, request.replyToSequence());
            if (exists == null || exists == 0) {
                throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "The message being replied to does not exist.");
            }
        }

        Long sequence = jdbc.queryForObject("""
                UPDATE conversations
                SET last_sequence = last_sequence + 1, updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
                RETURNING last_sequence
                """, Long.class, conversationId);
        UUID messageId = UUID.randomUUID();
        String body = request.body() == null ? "" : request.body().trim();
        String ciphertext = request.ciphertext() == null ? "" : request.ciphertext().trim();
        String contentType = request.contentType() == null ? "TEXT" : request.contentType();
        List<Map<String, Object>> attachments = request.attachments() == null
                ? List.of() : request.attachments();
        String attachmentsJson = writeAttachments(attachments);
        jdbc.update("""
                INSERT INTO messages (
                    conversation_id, sequence, id, sender_id, client_message_id,
                    body, ciphertext, encrypted, content_type, attachments,
                    reply_to_sequence)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb, ?)
                """, conversationId, sequence, messageId, senderId,
                request.clientMessageId(), request.encrypted() ? null : body,
                request.encrypted() ? ciphertext : null, request.encrypted(),
                contentType, attachmentsJson, request.replyToSequence());

        List<UUID> participants = conversations.participantIds(conversationId);
        for (UUID participantId : participants) {
            if (participantId.equals(senderId)) continue;
            jdbc.update("""
                    INSERT INTO message_receipts (conversation_id, sequence, user_id)
                    VALUES (?, ?, ?)
                    ON CONFLICT (conversation_id, sequence, user_id) DO NOTHING
                    """, conversationId, sequence, participantId);
        }
        ChatMessage saved = new ChatMessage(messageId, conversationId, sequence,
                senderId, request.clientMessageId(), body, ciphertext,
                request.encrypted(), contentType, attachments,
                request.replyToSequence(), Instant.now());
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("type", "message");
        event.put("recipients", participants.stream().map(UUID::toString).toList());
        event.putAll(saved.toMap());
        eventPublisher.enqueue(event);
        return saved;
    }

    @Transactional(readOnly = true)
    public MessagePage sync(UUID userId, UUID conversationId, long afterSequence, int limit) {
        conversations.requireParticipant(conversationId, userId);
        int safeLimit = Math.max(1, Math.min(limit, 100));
        List<ChatMessage> rows = jdbc.query("""
                SELECT id, conversation_id, sequence, sender_id, client_message_id,
                       body, ciphertext, encrypted, content_type, attachments::text AS attachments,
                       reply_to_sequence, created_at
                FROM messages
                WHERE conversation_id = ? AND sequence > ?
                ORDER BY sequence ASC
                LIMIT ?
                """, MESSAGE_ROW_MAPPER, conversationId, Math.max(0, afterSequence), safeLimit + 1);
        boolean hasMore = rows.size() > safeLimit;
        List<ChatMessage> pageRows = hasMore ? rows.subList(0, safeLimit) : rows;
        List<Map<String, Object>> messages = new ArrayList<>(pageRows.size());
        for (ChatMessage row : pageRows) {
            Map<String, Object> message = new LinkedHashMap<>(row.toMap());
            message.put("receiptSummary", receiptSummary(row.conversationId(), row.sequence()));
            messages.add(message);
        }
        Long lastSequence = jdbc.queryForObject(
                "SELECT last_sequence FROM conversations WHERE id = ?", Long.class,
                conversationId);
        return new MessagePage(List.copyOf(messages), lastSequence == null ? 0 : lastSequence,
                hasMore);
    }

    @Transactional
    public void markDelivered(UUID userId, UUID conversationId, long sequence) {
        markReceipt(userId, conversationId, sequence, "DELIVERED");
    }

    @Transactional
    public void markRead(UUID userId, UUID conversationId, long sequence) {
        markReceipt(userId, conversationId, sequence, "READ");
    }

    private void markReceipt(UUID userId, UUID conversationId, long sequence, String status) {
        conversations.requireParticipant(conversationId, userId);
        UUID senderId;
        try {
            senderId = jdbc.queryForObject("""
                    SELECT sender_id FROM messages
                    WHERE conversation_id = ? AND sequence = ?
                    """, UUID.class, conversationId, sequence);
        } catch (org.springframework.dao.EmptyResultDataAccessException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Message not found.");
        }
        if (senderId.equals(userId)) return;
        jdbc.update("""
                INSERT INTO message_receipts (conversation_id, sequence, user_id, delivered_at, read_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP, CASE WHEN ? = 'READ' THEN CURRENT_TIMESTAMP ELSE NULL END)
                ON CONFLICT (conversation_id, sequence, user_id) DO UPDATE
                SET delivered_at = COALESCE(message_receipts.delivered_at, EXCLUDED.delivered_at),
                    read_at = CASE WHEN ? = 'READ'
                        THEN COALESCE(message_receipts.read_at, CURRENT_TIMESTAMP)
                        ELSE message_receipts.read_at END
                """, conversationId, sequence, userId, status, status);
        if ("READ".equals(status)) {
            jdbc.update("""
                    UPDATE conversation_participants
                    SET last_read_sequence = GREATEST(last_read_sequence, ?)
                    WHERE conversation_id = ? AND user_id = ?
                    """, sequence, conversationId, userId);
        }
        Map<String, Object> event = Map.of(
                "type", "receipt",
                "recipients", List.of(senderId.toString()),
                "conversationId", conversationId.toString(),
                "sequence", sequence,
                "userId", userId.toString(),
                "status", status,
                "at", Instant.now().toString());
        eventPublisher.enqueue(event);
    }

    private List<Map<String, Object>> receiptSummary(UUID conversationId, long sequence) {
        return jdbc.query("""
                SELECT user_id, delivered_at, read_at
                FROM message_receipts
                WHERE conversation_id = ? AND sequence = ?
                ORDER BY user_id
                """, (rs, rowNum) -> {
                    Map<String, Object> receipt = new LinkedHashMap<>();
                    receipt.put("userId", rs.getObject("user_id", UUID.class).toString());
                    receipt.put("deliveredAt", rs.getTimestamp("delivered_at") == null
                            ? null : rs.getTimestamp("delivered_at").toInstant().toString());
                    receipt.put("readAt", rs.getTimestamp("read_at") == null
                            ? null : rs.getTimestamp("read_at").toInstant().toString());
                    return receipt;
                }, conversationId, sequence);
    }

    private void lockConversation(UUID conversationId, UUID userId) {
        List<UUID> rows = jdbc.query("""
                SELECT c.id FROM conversations c
                JOIN conversation_participants p ON p.conversation_id = c.id
                WHERE c.id = ? AND p.user_id = ?
                FOR UPDATE OF c
                """, (rs, rowNum) -> rs.getObject(1, UUID.class), conversationId, userId);
        if (rows.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "You are not a participant in this conversation.");
        }
    }

    private ChatMessage findByClientId(UUID conversationId, UUID senderId,
                                       UUID clientMessageId) {
        List<ChatMessage> messages = jdbc.query("""
                SELECT id, conversation_id, sequence, sender_id, client_message_id,
                       body, ciphertext, encrypted, content_type, attachments::text AS attachments,
                       reply_to_sequence, created_at
                FROM messages
                WHERE conversation_id = ? AND sender_id = ? AND client_message_id = ?
                """, MESSAGE_ROW_MAPPER, conversationId, senderId, clientMessageId);
        return messages.isEmpty() ? null : messages.getFirst();
    }

    private void validate(SendRequest request) {
        if (request == null || request.clientMessageId() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "clientMessageId is required for idempotent sending.");
        }
        String contentType = request.contentType() == null ? "TEXT" : request.contentType();
        if (!List.of("TEXT", "IMAGE", "AUDIO", "MIXED").contains(contentType)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unsupported message content type.");
        }
        List<Map<String, Object>> attachments = request.attachments() == null
                ? List.of() : request.attachments();
        if (attachments.size() > 10) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A message may contain at most ten attachments.");
        }
        String body = request.body() == null ? "" : request.body().trim();
        String ciphertext = request.ciphertext() == null ? "" : request.ciphertext().trim();
        if (request.encrypted()) {
            if (ciphertext.isEmpty() || ciphertext.length() > 64_000 || !body.isEmpty()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "Encrypted messages require ciphertext and cannot include plaintext.");
            }
        } else if (body.length() > 8_000 || (body.isEmpty() && attachments.isEmpty())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Messages need text or media and may contain at most 8000 text characters.");
        }
        for (Map<String, Object> attachment : attachments) {
            Object key = attachment.get("objectKey");
            if (key == null || key.toString().isBlank()
                    || key.toString().contains("..")
                    || attachment.containsKey("url")) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "Attachments must use a server-issued object storage key.");
            }
        }
    }

    private String writeAttachments(List<Map<String, Object>> attachments) {
        try {
            return objectMapper.writeValueAsString(attachments == null ? List.of() : attachments);
        } catch (JsonProcessingException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Attachment metadata is invalid.", exception);
        }
    }

    private List<Map<String, Object>> readAttachments(String json) {
        try {
            if (json == null) return List.of();
            return objectMapper.readValue(json, ATTACHMENTS_TYPE);
        } catch (Exception exception) {
            throw new IllegalStateException("Stored chat attachment metadata is invalid.", exception);
        }
    }

    private final RowMapper<ChatMessage> MESSAGE_ROW_MAPPER = (rs, rowNum) -> mapMessage(rs);

    private ChatMessage mapMessage(ResultSet rs) throws SQLException {
        return new ChatMessage(
                rs.getObject("id", UUID.class),
                rs.getObject("conversation_id", UUID.class),
                rs.getLong("sequence"),
                rs.getObject("sender_id", UUID.class),
                rs.getObject("client_message_id", UUID.class),
                rs.getString("body"),
                rs.getString("ciphertext"),
                rs.getBoolean("encrypted"),
                rs.getString("content_type"),
                readAttachments(rs.getString("attachments")),
                (Long) rs.getObject("reply_to_sequence"),
                rs.getTimestamp("created_at").toInstant());
    }
}
