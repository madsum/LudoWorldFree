package com.ludoworldfree.backend.chat;

import java.net.URI;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

@Service
public class ChatMediaUploadService {
    public record UploadRequest(String contentType, long byteSize, String sha256Hex) {}

    private static final Pattern SHA256 = Pattern.compile("[a-fA-F0-9]{64}");
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
    private final ChatConversationService conversations;
    private final S3Presigner presigner;
    private final String bucket;
    private final Duration uploadUrlDuration;
    private final Duration downloadUrlDuration;

    public ChatMediaUploadService(
            JdbcTemplate jdbc,
            ChatConversationService conversations,
            @Value("${chat.media.bucket:}") String bucket,
            @Value("${chat.media.region:eu-west-1}") String region,
            @Value("${chat.media.endpoint:}") String endpoint,
            @Value("${chat.media.upload-url-minutes:10}") long uploadUrlMinutes,
            @Value("${chat.media.download-url-minutes:5}") long downloadUrlMinutes) {
        this.jdbc = jdbc;
        this.conversations = conversations;
        this.bucket = bucket == null ? "" : bucket.trim();
        S3Presigner.Builder builder = S3Presigner.builder().region(Region.of(region));
        if (endpoint != null && !endpoint.isBlank()) {
            builder.endpointOverride(URI.create(endpoint));
        }
        this.presigner = builder.build();
        this.uploadUrlDuration = Duration.ofMinutes(Math.clamp(uploadUrlMinutes, 1, 15));
        this.downloadUrlDuration = Duration.ofMinutes(Math.clamp(downloadUrlMinutes, 1, 15));
    }

    @Transactional
    public Map<String, Object> createUpload(UUID userId, UUID conversationId,
                                           UploadRequest request) {
        conversations.requireParticipant(conversationId, userId);
        requireBucket();
        if (request == null || request.contentType() == null
                || !ALLOWED_TYPES.containsKey(request.contentType().toLowerCase())
                || request.byteSize() <= 0 || request.byteSize() > 20L * 1024 * 1024
                || request.sha256Hex() == null || !SHA256.matcher(request.sha256Hex()).matches()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a supported image, audio, or document up to 20 MB and provide its SHA-256 checksum.");
        }
        String contentType = request.contentType().toLowerCase();
        UUID uploadId = UUID.randomUUID();
        String objectKey = "chat/" + userId + "/" + uploadId;
        Instant expiresAt = Instant.now().plus(uploadUrlDuration);
        jdbc.update("""
                INSERT INTO chat_media_uploads (
                    id, conversation_id, owner_id, object_key, content_type,
                    byte_size, sha256_hex, expires_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, uploadId, conversationId, userId, objectKey, contentType,
                request.byteSize(), request.sha256Hex().toLowerCase(), expiresAt);

        PutObjectRequest put = PutObjectRequest.builder()
                .bucket(bucket)
                .key(objectKey)
                .contentType(contentType)
                .contentLength(request.byteSize())
                .checksumSHA256(Base64.getEncoder().encodeToString(
                        HexFormat.of().parseHex(request.sha256Hex())))
                .metadata(Map.of("sha256", request.sha256Hex().toLowerCase(),
                        "owner", userId.toString()))
                .build();
        var signed = presigner.presignPutObject(PutObjectPresignRequest.builder()
                .signatureDuration(uploadUrlDuration)
                .putObjectRequest(put)
                .build());
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("attachmentId", uploadId.toString());
        result.put("objectKey", objectKey);
        result.put("contentType", contentType);
        result.put("byteSize", request.byteSize());
        result.put("sha256Hex", request.sha256Hex().toLowerCase());
        result.put("uploadUrl", signed.url().toString());
        result.put("requiredHeaders", signed.signedHeaders());
        result.put("expiresAt", expiresAt.toString());
        return result;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> createDownload(UUID userId, UUID conversationId,
                                              UUID attachmentId) {
        conversations.requireParticipant(conversationId, userId);
        requireBucket();
        List<MediaUpload> rows = jdbc.query("""
                SELECT object_key, content_type, state, expires_at
                FROM chat_media_uploads
                WHERE id = ? AND conversation_id = ?
                """, (rs, rowNum) -> new MediaUpload(
                rs.getString("object_key"), rs.getString("content_type"),
                rs.getString("state"), rs.getTimestamp("expires_at").toInstant()),
                attachmentId, conversationId);
        if (rows.isEmpty() || !"ATTACHED".equals(rows.getFirst().state())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "This attachment is not available in the conversation.");
        }
        MediaUpload upload = rows.getFirst();
        GetObjectRequest get = GetObjectRequest.builder().bucket(bucket).key(upload.objectKey()).build();
        var signed = presigner.presignGetObject(GetObjectPresignRequest.builder()
                .signatureDuration(downloadUrlDuration)
                .getObjectRequest(get)
                .build());
        return Map.of("attachmentId", attachmentId.toString(),
                "downloadUrl", signed.url().toString(),
                "contentType", upload.contentType(),
                "expiresAt", Instant.now().plus(downloadUrlDuration).toString());
    }

    @Transactional
    public void attachUploads(UUID userId, UUID conversationId,
                              List<Map<String, Object>> attachments) {
        if (attachments == null || attachments.isEmpty()) return;
        for (Map<String, Object> attachment : attachments) {
            UUID id;
            try {
                id = UUID.fromString(String.valueOf(attachment.get("attachmentId")));
            } catch (IllegalArgumentException exception) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "Every media pointer needs a server-issued attachmentId.");
            }
            String objectKey = String.valueOf(attachment.get("objectKey"));
            String sha256Hex = String.valueOf(attachment.get("sha256Hex"));
            int changed = jdbc.update("""
                    UPDATE chat_media_uploads
                    SET state = 'ATTACHED', attached_at = CURRENT_TIMESTAMP
                    WHERE id = ? AND conversation_id = ? AND owner_id = ?
                      AND object_key = ? AND sha256_hex = ? AND state = 'PENDING'
                      AND expires_at > CURRENT_TIMESTAMP
                    """, id, conversationId, userId, objectKey, sha256Hex);
            if (changed == 0) {
                Integer attached = jdbc.queryForObject("""
                        SELECT COUNT(*) FROM chat_media_uploads
                        WHERE id = ? AND conversation_id = ? AND owner_id = ?
                          AND object_key = ? AND sha256_hex = ? AND state = 'ATTACHED'
                        """, Integer.class, id, conversationId, userId, objectKey, sha256Hex);
                if (attached == null || attached == 0) {
                    throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                            "The media pointer is invalid, expired, or belongs to another user.");
                }
            }
        }
    }

    private void requireBucket() {
        if (bucket.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Chat media storage is not configured.");
        }
    }

    private record MediaUpload(String objectKey, String contentType,
                               String state, Instant expiresAt) {}
}
