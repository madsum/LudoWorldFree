package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.model.ChatMessage;
import com.ludoworldfree.backend.model.Friendship;
import com.ludoworldfree.backend.repository.ChatMessageRepository;
import com.ludoworldfree.backend.repository.FriendshipRepository;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/friends/{friendId}/messages")
public class ChatController {
    private final ChatMessageRepository messageRepository;
    private final FriendshipRepository friendshipRepository;

    public ChatController(ChatMessageRepository messageRepository,
                          FriendshipRepository friendshipRepository) {
        this.messageRepository = messageRepository;
        this.friendshipRepository = friendshipRepository;
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
            @RequestBody Map<String, String> body) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        requireAcceptedFriendship(playerId, friendId);
        String content = body.getOrDefault("content", "").trim();
        if (content.isEmpty() || content.length() > 1000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Messages must contain 1 to 1000 characters.");
        }
        return messageResponse(messageRepository.save(
                new ChatMessage(playerId, friendId, content)));
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
        result.put("createdAt", message.getCreatedAt().toString());
        return result;
    }
}
