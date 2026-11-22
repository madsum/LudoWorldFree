package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.model.Friendship;
import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.repository.FriendshipRepository;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import com.ludoworldfree.backend.websocket.VoiceCallWebSocketHandler;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.data.domain.PageRequest;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/friends")
public class FriendshipController {
    private final FriendshipRepository friendshipRepository;
    private final PlayerProfileRepository profileRepository;
    private final VoiceCallWebSocketHandler voiceCallHandler;

    public FriendshipController(FriendshipRepository friendshipRepository,
                                PlayerProfileRepository profileRepository,
                                VoiceCallWebSocketHandler voiceCallHandler) {
        this.friendshipRepository = friendshipRepository;
        this.profileRepository = profileRepository;
        this.voiceCallHandler = voiceCallHandler;
    }

    @GetMapping
    public Map<String, Object> list(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        List<Map<String, Object>> entries = new ArrayList<>();
        List<Friendship> friendships = friendshipRepository
                .findAllByRequesterIdOrAddresseeId(playerId, playerId);
        Set<UUID> friendIds = new LinkedHashSet<>();
        for (Friendship friendship : friendships) {
            friendIds.add(friendship.getRequesterId().equals(playerId)
                    ? friendship.getAddresseeId() : friendship.getRequesterId());
        }
        Map<UUID, PlayerProfile> profiles = new LinkedHashMap<>();
        for (PlayerProfile profile : profileRepository.findByUserIdIn(friendIds)) {
            profiles.put(profile.getUserId(), profile);
        }
        Map<UUID, Boolean> onlineStatuses = voiceCallHandler.onlineStatuses(friendIds);

        for (Friendship friendship : friendships) {
            UUID otherId = friendship.getRequesterId().equals(playerId)
                    ? friendship.getAddresseeId() : friendship.getRequesterId();
            PlayerProfile profile = profiles.get(otherId);
            Map<String, Object> entry = new LinkedHashMap<>();
            entry.put("id", friendship.getId().toString());
            entry.put("playerId", otherId.toString());
            entry.put("displayName", profile == null ? "Player" : profile.getDisplayName());
            entry.put("avatarUrl", profile == null ? null : profile.getAvatarUrl());
            entry.put("countryFlag", profile == null ? "🌐" : profile.getCountryFlag());
            entry.put("online", onlineStatuses.getOrDefault(otherId, false));
            entry.put("status", friendship.getStatus().name());
            entry.put("direction", friendship.getRequesterId().equals(playerId)
                    ? "OUTGOING" : "INCOMING");
            entries.add(entry);
        }
        return Map.of("entries", entries);
    }

    @GetMapping("/incoming-requests")
    public Map<String, Object> incomingRequests(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        List<Map<String, Object>> entries = new ArrayList<>();
        for (Friendship friendship : friendshipRepository
                .findAllByRequesterIdOrAddresseeId(playerId, playerId)) {
            if (!friendship.getAddresseeId().equals(playerId)
                    || friendship.getStatus() != Friendship.Status.PENDING) {
                continue;
            }
            PlayerProfile profile = profileRepository
                    .findByUserId(friendship.getRequesterId()).orElse(null);
            Map<String, Object> entry = new LinkedHashMap<>();
            entry.put("id", friendship.getId().toString());
            entry.put("playerId", friendship.getRequesterId().toString());
            entry.put("displayName", profile == null ? "Player" : profile.getDisplayName());
            entry.put("avatarUrl", profile == null ? null : profile.getAvatarUrl());
            entry.put("countryFlag", profile == null ? "🌐" : profile.getCountryFlag());
            entry.put("status", friendship.getStatus().name());
            entries.add(entry);
        }
        return Map.of("entries", entries);
    }

    @GetMapping("/outgoing-requests")
    public Map<String, Object> outgoingRequests(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestParam(value = "after", required = false) String after) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        java.time.Instant cursor = java.time.Instant.now();
        java.time.Instant afterInstant;
        try {
            afterInstant = after == null ? cursor.minusSeconds(60)
                    : java.time.Instant.parse(after);
        } catch (RuntimeException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A valid update cursor is required.");
        }
        List<Map<String, Object>> entries = new ArrayList<>();
        for (Friendship friendship : friendshipRepository
                .findByRequesterIdAndUpdatedAtAfterOrderByUpdatedAtAsc(
                        playerId, afterInstant, PageRequest.of(0, 30))) {
            PlayerProfile profile = profileRepository
                    .findByUserId(friendship.getAddresseeId()).orElse(null);
            Map<String, Object> entry = new LinkedHashMap<>();
            entry.put("id", friendship.getId().toString());
            entry.put("playerId", friendship.getAddresseeId().toString());
            entry.put("displayName", profile == null ? "Player" : profile.getDisplayName());
            entry.put("status", friendship.getStatus().name());
            entry.put("updatedAt", friendship.getUpdatedAt().toString());
            entries.add(entry);
        }
        return Map.of("entries", entries, "cursor", cursor.toString());
    }

    @PostMapping("/requests")
    @Transactional
    public Map<String, Object> sendRequest(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestBody Map<String, String> body) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        UUID targetId = parsePlayerId(body.get("playerId"));
        if (playerId.equals(targetId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "You cannot add yourself.");
        }
        if (!profileRepository.existsByUserId(targetId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Player not found.");
        }

        var existing = friendshipRepository.findByRequesterIdAndAddresseeId(playerId, targetId);
        if (existing.isPresent()) {
            Friendship friendship = existing.get();
            Map<String, Object> response = new LinkedHashMap<>(friendshipResponse(friendship));
            response.put("alreadyBuddy", friendship.getStatus() == Friendship.Status.ACCEPTED);
            return response;
        }

        var incoming = friendshipRepository.findByRequesterIdAndAddresseeId(targetId, playerId);
        if (incoming.isPresent()) {
            Friendship friendship = incoming.get();
            friendship.accept();
            Map<String, Object> response = new LinkedHashMap<>(
                    friendshipResponse(friendshipRepository.save(friendship)));
            response.put("alreadyBuddy", false);
            return response;
        }
        Map<String, Object> response = new LinkedHashMap<>(
                friendshipResponse(friendshipRepository.save(new Friendship(playerId, targetId))));
        response.put("alreadyBuddy", false);
        return response;
    }

    @PostMapping("/{friendshipId}/accept")
    @Transactional
    public Map<String, Object> accept(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID friendshipId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        Friendship friendship = findForPlayer(friendshipId, playerId);
        if (!friendship.getAddresseeId().equals(playerId)
                || friendship.getStatus() != Friendship.Status.PENDING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "This request cannot be accepted.");
        }
        friendship.accept();
        return friendshipResponse(friendshipRepository.save(friendship));
    }

    @PostMapping("/{friendshipId}/decline")
    @Transactional
    public Map<String, Object> decline(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID friendshipId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        Friendship friendship = findForPlayer(friendshipId, playerId);
        if (!friendship.getAddresseeId().equals(playerId)
                || friendship.getStatus() != Friendship.Status.PENDING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "This request cannot be declined.");
        }
        friendship.reject();
        return friendshipResponse(friendshipRepository.save(friendship));
    }

    @DeleteMapping("/{friendshipId}")
    @Transactional
    public Map<String, Object> remove(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID friendshipId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        Friendship friendship = findForPlayer(friendshipId, playerId);
        friendshipRepository.delete(friendship);
        return Map.of("success", true);
    }

    private Friendship findForPlayer(UUID friendshipId, UUID playerId) {
        Friendship friendship = friendshipRepository.findById(friendshipId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Friend request not found."));
        if (!friendship.getRequesterId().equals(playerId)
                && !friendship.getAddresseeId().equals(playerId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "This friend request belongs to another player.");
        }
        return friendship;
    }

    private static UUID parsePlayerId(String value) {
        try {
            return UUID.fromString(value);
        } catch (RuntimeException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "A valid playerId is required.");
        }
    }

    private static Map<String, Object> friendshipResponse(Friendship friendship) {
        return Map.of("id", friendship.getId().toString(), "status", friendship.getStatus().name());
    }
}
