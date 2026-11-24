package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.model.ChatMessage;
import com.ludoworldfree.backend.model.Friendship;
import com.ludoworldfree.backend.repository.ChatMessageRepository;
import com.ludoworldfree.backend.repository.FriendshipRepository;
import com.ludoworldfree.backend.chat.ChatConversationService;
import com.ludoworldfree.backend.chat.ChatMediaUploadService;
import com.ludoworldfree.backend.chat.BuddyChatAttachmentService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.LinkedHashMap;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/friends/{friendId}/messages")
public class ChatController {
    private final ChatMessageRepository messageRepository;
    private final FriendshipRepository friendshipRepository;
    private final ChatConversationService conversations;
    private final ChatMediaUploadService mediaUploads;
    private final BuddyChatAttachmentService buddyAttachments;

    public ChatController(ChatMessageRepository messageRepository,
                          FriendshipRepository friendshipRepository,
                          ChatConversationService conversations,
                          ChatMediaUploadService mediaUploads,
                          BuddyChatAttachmentService buddyAttachments) {
        this.messageRepository = messageRepository;
        this.friendshipRepository = friendshipRepository;
        this.conversations = conversations;
        this.mediaUploads = mediaUploads;
        this.buddyAttachments = buddyAttachments;
    }

    @GetMapping
    @Transactional
    public Map<String, Object> conversation(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID friendId,
            @RequestParam(defaultValue = "100") int limit) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        requireAcceptedFriendship(playerId, friendId);
        messageRepository.markConversationRead(playerId, friendId, java.time.Instant.now());
        int safeLimit = Math.max(1, Math.min(limit, 100));
        List<Map<String, Object>> messages = messageRepository.findConversation(
                        playerId, friendId, PageRequest.of(0, safeLimit))
                .stream()
                .sorted(java.util.Comparator.comparing(ChatMessage::getCreatedAt))
                .map(ChatController::messageResponse)
                .toList();
        return Map.of("messages", messages);
    }

    @PostMapping
    @Transactional
    public Map<String, Object> send(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID friendId,
            @RequestBody Map<String, Object> body) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        requireAcceptedFriendship(playerId, friendId);
        String content = body.get("content") == null
                ? "" : body.get("content").toString().trim();
        List<Map<String, Object>> attachments = readAttachments(body.get("attachments"));
        if (content.length() > 1000 || (content.isEmpty() && attachments.isEmpty())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Messages need text or at least one file, with text up to 1000 characters.");
        }
        if (attachments.size() > 10) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A message may contain at most ten files.");
        }
        if (!attachments.isEmpty()) {
            boolean databaseAttachments = attachments.stream()
                    .allMatch(attachment -> "database".equals(attachment.get("storage")));
            boolean mixedStorage = attachments.stream().anyMatch(attachment ->
                    "database".equals(attachment.get("storage"))) && !databaseAttachments;
            if (mixedStorage) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "Files uploaded using different storage methods cannot share one message.");
            }
            if (!databaseAttachments) {
                mediaUploads.attachUploads(playerId,
                        conversations.createDirect(playerId, friendId), attachments);
            }
        }
        boolean databaseAttachments = !attachments.isEmpty()
                && "database".equals(attachments.getFirst().get("storage"));
        ChatMessage message = new ChatMessage(playerId, friendId, content,
                databaseAttachments ? List.of() : attachments);
        if (databaseAttachments) {
            message = messageRepository.saveAndFlush(message);
            message.setAttachments(buddyAttachments.attachUploads(
                    playerId, friendId, message.getId(), attachments));
        }
        return messageResponse(messageRepository.save(message));
    }

    @PostMapping("/media/uploads")
    public Map<String, Object> createMediaUpload(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID friendId,
            @RequestBody ChatMediaUploadService.UploadRequest request) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        requireAcceptedFriendship(playerId, friendId);
        return mediaUploads.createUpload(playerId,
                conversations.createDirect(playerId, friendId), request);
    }

    @PostMapping(value = "/media/uploads", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public Map<String, Object> uploadBuddyAttachment(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID friendId,
            @RequestParam("file") MultipartFile file,
            @RequestParam("contentType") String contentType) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        requireAcceptedFriendship(playerId, friendId);
        return buddyAttachments.upload(playerId, friendId, file, contentType);
    }

    @GetMapping("/media/{attachmentId}")
    public ResponseEntity<?> downloadMedia(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID friendId,
            @PathVariable UUID attachmentId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        requireAcceptedFriendship(playerId, friendId);
        BuddyChatAttachmentService.Download file = buddyAttachments.findDownload(
                playerId, friendId, attachmentId);
        if (file != null) {
            return ResponseEntity.ok()
                    .contentType(MediaType.parseMediaType(file.contentType()))
                    .header(HttpHeaders.CONTENT_DISPOSITION,
                            ContentDisposition.attachment()
                                    .filename(file.fileName(), java.nio.charset.StandardCharsets.UTF_8)
                                    .build().toString())
                    .body(file.bytes());
        }
        return ResponseEntity.ok(mediaUploads.createDownload(playerId,
                conversations.createDirect(playerId, friendId), attachmentId));
    }

    private void requireAcceptedFriendship(UUID playerId, UUID friendId) {
        boolean accepted = friendshipRepository
                .findByRequesterIdAndAddresseeId(playerId, friendId)
                .map(friendship -> friendship.getStatus() == Friendship.Status.ACCEPTED)
                .orElseGet(() -> friendshipRepository
                        .findByRequesterIdAndAddresseeId(friendId, playerId)
                        .map(friendship -> friendship.getStatus() == Friendship.Status.ACCEPTED)
                        .orElse(false));
        if (!accepted) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Chat is available only between accepted friends.");
        }
    }

    private static Map<String, Object> messageResponse(ChatMessage message) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("id", message.getId().toString());
        result.put("senderId", message.getSenderId().toString());
        result.put("recipientId", message.getRecipientId().toString());
        result.put("content", message.getContent());
        result.put("type", message.getMessageType().name());
        result.put("attachments", message.getAttachments());
        result.put("createdAt", message.getCreatedAt().toString());
        return result;
    }

    private List<Map<String, Object>> readAttachments(Object rawAttachments) {
        if (rawAttachments == null) return List.of();
        if (!(rawAttachments instanceof List<?> rawList)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "File attachments must be provided as a list.");
        }
        List<Map<String, Object>> attachments = new ArrayList<>();
        for (Object raw : rawList) {
            if (!(raw instanceof Map<?, ?> rawMap)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "A file attachment is invalid.");
            }
            Map<String, Object> attachment = new LinkedHashMap<>();
            rawMap.forEach((key, value) -> {
                if (key instanceof String stringKey) attachment.put(stringKey, value);
            });
            attachments.add(attachment);
        }
        return attachments;
    }
}
