package com.ludoworldfree.backend.service;

import com.ludoworldfree.backend.model.OnlineMatchChatEvent;
import com.ludoworldfree.backend.repository.OnlineMatchChatEventRepository;
import com.ludoworldfree.backend.realtime.DatabaseRealtimeEventBus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Collection;
import java.util.UUID;

@Service
public class OnlineMatchChatService {
    private final OnlineMatchChatEventRepository repository;
    private final DatabaseRealtimeEventBus realtimeEvents;

    public OnlineMatchChatService(OnlineMatchChatEventRepository repository,
                                  DatabaseRealtimeEventBus realtimeEvents) {
        this.repository = repository;
        this.realtimeEvents = realtimeEvents;
    }

    @Transactional
    public ChatEvent save(String roomId, UUID playerId, String text) {
        OnlineMatchChatEvent event = repository.saveAndFlush(
                new OnlineMatchChatEvent(roomId, playerId, text));
        ChatEvent saved = toChatEvent(event);
        publish(saved);
        return saved;
    }

    @Transactional
    public ChatEvent saveTypingStatus(String roomId, UUID playerId, boolean isTyping) {
        String eventType = isTyping ? "TYPING_START" : "TYPING_STOP";
        OnlineMatchChatEvent event = repository.saveAndFlush(
                new OnlineMatchChatEvent(roomId, playerId, "", eventType));
        ChatEvent saved = toChatEvent(event);
        publish(saved);
        return saved;
    }

    @Transactional
    public ChatEvent saveControlEvent(String roomId, UUID playerId, String payload) {
        if (payload == null || payload.length() > 200) {
            throw new IllegalArgumentException("Room control events must be 200 characters or fewer.");
        }
        OnlineMatchChatEvent event = repository.saveAndFlush(
                new OnlineMatchChatEvent(roomId, playerId, payload, "GAME_CONTROL"));
        ChatEvent saved = toChatEvent(event);
        publish(saved);
        return saved;
    }

    @Transactional(readOnly = true)
    public List<ChatEvent> after(String roomId, long eventId) {
        return repository.findByRoomIdAndIdGreaterThanOrderByIdAsc(roomId, eventId)
                .stream().map(OnlineMatchChatService::toChatEvent).toList();
    }

    @Transactional(readOnly = true)
    public List<ChatEvent> after(Collection<String> roomIds, long minimumEventId) {
        if (roomIds == null || roomIds.isEmpty()) return List.of();
        return repository.findByRoomIdInAndIdGreaterThanOrderByIdAsc(roomIds, minimumEventId)
                .stream().map(OnlineMatchChatService::toChatEvent).toList();
    }

    private static ChatEvent toChatEvent(OnlineMatchChatEvent event) {
        return new ChatEvent(event.getId(), event.getRoomId(), event.getPlayerId(), event.getText(),
                event.getEventType(), event.getCreatedAt());
    }

    private void publish(ChatEvent event) {
        realtimeEvents.publish(java.util.Map.of(
                "route", "game_room",
                "kind", "room_chat",
                "roomId", event.roomId(),
                "eventId", event.id(),
                "playerId", event.playerId().toString(),
                "text", event.text(),
                "eventType", event.eventType(),
                "createdAt", event.createdAt().toEpochMilli()));
    }

    public record ChatEvent(long id, String roomId, UUID playerId, String text, String eventType,
                            Instant createdAt) {}
}
