package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.model.ChatMessage;
import com.ludoworldfree.backend.model.Friendship;
import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.repository.ChatMessageRepository;
import com.ludoworldfree.backend.repository.FriendshipRepository;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/friends/inbox")
public class FriendMessageInboxController {
    private final ChatMessageRepository messageRepository;
    private final FriendshipRepository friendshipRepository;
    private final PlayerProfileRepository profileRepository;

    public FriendMessageInboxController(
            ChatMessageRepository messageRepository,
            FriendshipRepository friendshipRepository,
            PlayerProfileRepository profileRepository) {
        this.messageRepository = messageRepository;
        this.friendshipRepository = friendshipRepository;
        this.profileRepository = profileRepository;
    }

    @GetMapping
    public Map<String, Object> incomingMessages(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestParam(required = false) String after) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        Instant cursor = Instant.now();
        Instant afterInstant = parseAfter(after, cursor);

        Set<UUID> acceptedBuddyIds = friendshipRepository
                .findAllByRequesterIdOrAddresseeId(playerId, playerId)
                .stream()
                .filter(friendship -> friendship.getStatus() == Friendship.Status.ACCEPTED)
                .map(friendship -> friendship.getRequesterId().equals(playerId)
                        ? friendship.getAddresseeId() : friendship.getRequesterId())
                .collect(Collectors.toSet());

        List<Map<String, Object>> messages = new ArrayList<>();
        for (ChatMessage message : messageRepository
                .findByRecipientIdAndCreatedAtAfterOrderByCreatedAtAsc(
                        playerId, afterInstant, PageRequest.of(0, 100))) {
            if (!acceptedBuddyIds.contains(message.getSenderId())) continue;
            PlayerProfile sender = profileRepository
                    .findByUserId(message.getSenderId()).orElse(null);
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("id", message.getId().toString());
            item.put("senderId", message.getSenderId().toString());
            item.put("senderName", sender == null ? "Buddy" : sender.getDisplayName());
            item.put("content", message.getContent());
            item.put("createdAt", message.getCreatedAt().toString());
            messages.add(item);
        }
        return Map.of("cursor", cursor.toString(), "messages", messages);
    }

    private static Instant parseAfter(String value, Instant fallback) {
        if (value == null || value.isBlank()) return fallback;
        try {
            return Instant.parse(value);
        } catch (DateTimeParseException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A valid inbox cursor is required.");
        }
    }
}
