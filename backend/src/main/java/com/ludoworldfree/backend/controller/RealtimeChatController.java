package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.chat.ChatConversationService;
import com.ludoworldfree.backend.chat.ChatDirectoryService;
import com.ludoworldfree.backend.chat.ChatMessage;
import com.ludoworldfree.backend.chat.ChatMessageService;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/chat")
public class RealtimeChatController {
    public record DirectConversationRequest(UUID userId) {}
    public record GroupConversationRequest(String title, List<UUID> memberIds) {}
    public record ReceiptRequest(long sequence) {}

    private final ChatDirectoryService directory;
    private final ChatConversationService conversations;
    private final ChatMessageService messages;

    public RealtimeChatController(ChatDirectoryService directory,
                                  ChatConversationService conversations,
                                  ChatMessageService messages) {
        this.directory = directory;
        this.conversations = conversations;
        this.messages = messages;
    }

    @GetMapping("/me")
    public Map<String, Object> me(@AuthenticationPrincipal Jwt jwt) {
        return directory.profile(userId(jwt));
    }

    @PatchMapping("/me")
    public Map<String, Object> updateProfile(@AuthenticationPrincipal Jwt jwt,
                                             @RequestBody ChatDirectoryService.ProfileUpdate request) {
        return directory.updateProfile(userId(jwt), request);
    }

    @GetMapping("/contacts")
    public Map<String, Object> contacts(@AuthenticationPrincipal Jwt jwt,
                                        @RequestParam(required = false) String q) {
        return Map.of("contacts", directory.contacts(userId(jwt), q));
    }

    @PostMapping("/conversations/direct")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> createDirect(@AuthenticationPrincipal Jwt jwt,
                                           @RequestBody DirectConversationRequest request) {
        UUID conversationId = conversations.createDirect(userId(jwt), request.userId());
        return Map.of("conversationId", conversationId.toString(), "type", "DIRECT");
    }

    @PostMapping("/conversations/groups")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> createGroup(@AuthenticationPrincipal Jwt jwt,
                                           @RequestBody GroupConversationRequest request) {
        UUID conversationId = conversations.createGroup(userId(jwt), request.title(),
                request.memberIds());
        return Map.of("conversationId", conversationId.toString(), "type", "GROUP");
    }

    @GetMapping("/conversations")
    public Map<String, Object> conversations(@AuthenticationPrincipal Jwt jwt) {
        return Map.of("conversations", conversations.listForUser(userId(jwt)));
    }

    @GetMapping("/conversations/{conversationId}/messages")
    public ChatMessageService.MessagePage sync(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID conversationId,
            @RequestParam(defaultValue = "0") long afterSequence,
            @RequestParam(defaultValue = "100") int limit) {
        return messages.sync(userId(jwt), conversationId, afterSequence, limit);
    }

    @PostMapping("/conversations/{conversationId}/messages")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> send(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID conversationId,
            @RequestBody ChatMessageService.SendRequest request) {
        ChatMessage message = messages.send(userId(jwt), conversationId, request);
        return message.toMap();
    }

    @PostMapping("/conversations/{conversationId}/delivered")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delivered(@AuthenticationPrincipal Jwt jwt,
                          @PathVariable UUID conversationId,
                          @RequestBody ReceiptRequest request) {
        messages.markDelivered(userId(jwt), conversationId, request.sequence());
    }

    @PostMapping("/conversations/{conversationId}/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void read(@AuthenticationPrincipal Jwt jwt,
                     @PathVariable UUID conversationId,
                     @RequestBody ReceiptRequest request) {
        messages.markRead(userId(jwt), conversationId, request.sequence());
    }

    private UUID userId(Jwt jwt) {
        try {
            return UUID.fromString(jwt.getSubject());
        } catch (RuntimeException exception) {
            throw new org.springframework.web.server.ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "JWT subject must be a player UUID.");
        }
    }
}
