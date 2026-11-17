package com.ludoworldfree.backend.service;

import com.ludoworldfree.backend.model.OnlineMatchChatEvent;
import com.ludoworldfree.backend.repository.OnlineMatchChatEventRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
public class OnlineMatchChatService {
    private final OnlineMatchChatEventRepository repository;

    public OnlineMatchChatService(OnlineMatchChatEventRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public ChatEvent save(String roomId, UUID playerId, String text) {
        OnlineMatchChatEvent event = repository.saveAndFlush(
                new OnlineMatchChatEvent(roomId, playerId, text));
        return toChatEvent(event);
    }

    @Transactional
    public ChatEvent saveTypingStatus(String roomId, UUID playerId, boolean isTyping) {
        String eventType = isTyping ? "TYPING_START" : "TYPING_STOP";
        OnlineMatchChatEvent event = repository.saveAndFlush(
                new OnlineMatchChatEvent(roomId, playerId, "", eventType));
        return toChatEvent(event);
    }

    @Transactional
    public ChatEvent saveControlEvent(String roomId, UUID playerId, String payload) {
        if (payload == null || payload.length() > 200) {
            throw new IllegalArgumentException("Room control events must be 200 characters or fewer.");
        }
        OnlineMatchChatEvent event = repository.saveAndFlush(
                new OnlineMatchChatEvent(roomId, playerId, payload, "GAME_CONTROL"));
        return toChatEvent(event);
    }

    @Transactional(readOnly = true)
    public List<ChatEvent> after(String roomId, long eventId) {
        return repository.findByRoomIdAndIdGreaterThanOrderByIdAsc(roomId, eventId)
                .stream().map(OnlineMatchChatService::toChatEvent).toList();
    }

    private static ChatEvent toChatEvent(OnlineMatchChatEvent event) {
        return new ChatEvent(event.getId(), event.getPlayerId(), event.getText(),
                event.getEventType(), event.getCreatedAt());
    }

    public record ChatEvent(long id, UUID playerId, String text, String eventType,
                            Instant createdAt) {}
}
