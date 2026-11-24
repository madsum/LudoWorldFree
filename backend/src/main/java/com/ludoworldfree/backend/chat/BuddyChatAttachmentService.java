package com.ludoworldfree.backend.chat;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

@Service
public class BuddyChatAttachmentService {
    private static final long MAX_SIZE = 20L * 1024 * 1024;
    private static final Map<String, String> ALLOWED_TYPES = Map.ofEntries(
            Map.entry("image/jpeg", "IMAGE"),
            Map.entry("image/png", "IMAGE"),
            Map.entry("image/webp", "IMAGE"),
            Map.entry("image/gif", "IMAGE"),
            Map.entry("audio/aac", "AUDIO"),
            Map.entry("audio/mpeg", "AUDIO"),
            Map.entry("audio/mp4", "AUDIO"),
            Map.entry("audio/ogg", "AUDIO"),
            Map.entry("audio/wav", "AUDIO"),
            Map.entry("audio/webm", "AUDIO"),
            Map.entry("application/pdf", "FILE"),
            Map.entry("text/plain", "FILE"),
            Map.entry("text/csv", "FILE"),
            Map.entry("application/zip", "FILE"),
            Map.entry("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "FILE"),
            Map.entry("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "FILE"),
            Map.entry("application/vnd.openxmlformats-officedocument.presentationml.presentation", "FILE"),
            Map.entry("application/msword", "FILE"),
            Map.entry("application/vnd.ms-excel", "FILE"),
            Map.entry("application/vnd.ms-powerpoint", "FILE"));

    private final JdbcTemplate jdbc;

    public BuddyChatAttachmentService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Transactional
    public Map<String, Object> upload(UUID senderId, UUID recipientId,
                                      MultipartFile file, String requestedType) {
        String contentType = requestedType == null ? "" : requestedType.trim().toLowerCase();
        if (file == null || file.isEmpty() || file.getSize() > MAX_SIZE
                || !ALLOWED_TYPES.containsKey(contentType)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a supported file up to 20 MB.");
        }
        byte[] bytes;
        try {
            bytes = file.getBytes();
        } catch (java.io.IOException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "The selected file could not be read.", exception);
        }
        if (bytes.length == 0 || bytes.length > MAX_SIZE) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a supported file up to 20 MB.");
        }

        UUID id = UUID.randomUUID();
        String fileName = safeFileName(file.getOriginalFilename());
        String sha256Hex = sha256(bytes);
        jdbc.update("""
                INSERT INTO buddy_chat_attachments (
                    id, sender_id, recipient_id, file_name, content_type,
                    byte_size, sha256_hex, file_data)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, id, senderId, recipientId, fileName, contentType,
                bytes.length, sha256Hex, bytes);
        return Map.of("attachmentId", id.toString(), "fileName", fileName,
                "contentType", contentType, "byteSize", bytes.length,
                "sha256Hex", sha256Hex, "storage", "database");
    }

    @Transactional
    public List<Map<String, Object>> attachUploads(
            UUID senderId, UUID recipientId, UUID messageId,
            List<Map<String, Object>> requestedAttachments) {
        List<Map<String, Object>> attached = new ArrayList<>();
        long totalByteSize = 0;
        for (Map<String, Object> request : requestedAttachments) {
            UUID attachmentId;
            try {
                attachmentId = UUID.fromString(String.valueOf(request.get("attachmentId")));
            } catch (IllegalArgumentException exception) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "A file attachment is invalid.");
            }
            String sha256Hex = String.valueOf(request.get("sha256Hex"));
            List<Map<String, Object>> rows = jdbc.query("""
                    SELECT file_name, content_type, byte_size, sha256_hex
                    FROM buddy_chat_attachments
                    WHERE id = ? AND sender_id = ? AND recipient_id = ?
                      AND sha256_hex = ? AND message_id IS NULL
                    """, (rs, rowNum) -> Map.of(
                    "fileName", rs.getString("file_name"),
                    "contentType", rs.getString("content_type"),
                    "byteSize", rs.getLong("byte_size"),
                    "sha256Hex", rs.getString("sha256_hex")),
                    attachmentId, senderId, recipientId, sha256Hex);
            if (rows.isEmpty()) {
                throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                        "The uploaded file is invalid, expired, or already attached.");
            }
            totalByteSize += ((Number) rows.getFirst().get("byteSize")).longValue();
            if (totalByteSize > MAX_SIZE) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "Files in one message must total 20 MB or less.");
            }
            int changed = jdbc.update("""
                    UPDATE buddy_chat_attachments SET message_id = ?
                    WHERE id = ? AND sender_id = ? AND recipient_id = ?
                      AND sha256_hex = ? AND message_id IS NULL
                    """, messageId, attachmentId, senderId, recipientId, sha256Hex);
            if (changed != 1) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "This file has already been attached to a message.");
            }
            Map<String, Object> metadata = new java.util.LinkedHashMap<>(rows.getFirst());
            metadata.put("attachmentId", attachmentId.toString());
            metadata.put("storage", "database");
            attached.add(metadata);
        }
        return List.copyOf(attached);
    }

    @Transactional(readOnly = true)
    public Download findDownload(UUID requesterId, UUID friendId, UUID attachmentId) {
        List<Download> rows = jdbc.query("""
                SELECT file_name, content_type, file_data
                FROM buddy_chat_attachments
                WHERE id = ? AND message_id IS NOT NULL
                  AND ((sender_id = ? AND recipient_id = ?)
                    OR (sender_id = ? AND recipient_id = ?))
                """, (rs, rowNum) -> new Download(
                rs.getString("file_name"), rs.getString("content_type"),
                rs.getBytes("file_data")),
                attachmentId, requesterId, friendId, friendId, requesterId);
        return rows.isEmpty() ? null : rows.getFirst();
    }

    @Scheduled(fixedDelayString = "${buddy-chat.attachments.cleanup-millis:3600000}")
    public void removeUnattachedUploads() {
        jdbc.update("""
                DELETE FROM buddy_chat_attachments
                WHERE message_id IS NULL
                  AND created_at < CURRENT_TIMESTAMP - INTERVAL '24 hours'
                """);
    }

    private static String safeFileName(String value) {
        String name = value == null ? "attached-file" : value.replace('\\', '/');
        name = name.substring(name.lastIndexOf('/') + 1).trim();
        if (name.isEmpty()) name = "attached-file";
        name = name.replaceAll("[\\p{Cntrl}]", "_");
        return name.length() > 255 ? name.substring(name.length() - 255) : name;
    }

    private static String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is not available.", exception);
        }
    }

    public record Download(String fileName, String contentType, byte[] bytes) {}
}
