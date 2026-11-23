package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.dto.MatchmakingResponseDto;
import com.ludoworldfree.backend.model.BuddyGameInvitation;
import com.ludoworldfree.backend.model.Friendship;
import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.repository.BuddyGameInvitationRepository;
import com.ludoworldfree.backend.repository.FriendshipRepository;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import com.ludoworldfree.backend.service.MatchmakingService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/friends")
public class BuddyGameInvitationController {
    private static final Set<Long> ALLOWED_ENTRY_FEES = Set.of(
            250L, 500L, 1_000L, 2_000L, 4_000L, 8_000L,
            16_000L, 25_000L, 50_000L, 100_000L);

    private final BuddyGameInvitationRepository invitationRepository;
    private final FriendshipRepository friendshipRepository;
    private final PlayerProfileRepository profileRepository;
    private final MatchmakingService matchmakingService;

    public BuddyGameInvitationController(
            BuddyGameInvitationRepository invitationRepository,
            FriendshipRepository friendshipRepository,
            PlayerProfileRepository profileRepository,
            MatchmakingService matchmakingService) {
        this.invitationRepository = invitationRepository;
        this.friendshipRepository = friendshipRepository;
        this.profileRepository = profileRepository;
        this.matchmakingService = matchmakingService;
    }

    @PostMapping("/{friendId}/game-invites")
    @Transactional
    public Map<String, Object> invite(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID friendId,
            @RequestBody Map<String, Object> body) {
        UUID requesterId = PlayerIdResolver.resolve(headerPlayerId);
        requireAcceptedBuddies(requesterId, friendId);

        long entryFee = ((Number) body.getOrDefault("entryFee", 0)).longValue();
        if (!ALLOWED_ENTRY_FEES.contains(entryFee)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a supported online entry amount.");
        }
        String sessionId = text(body.get("sessionId"));
        String selectedColor = text(body.get("selectedColor"));
        String gameMode = text(body.get("gameMode"));
        if (gameMode == null) gameMode = "CLASSIC";
        gameMode = gameMode.strip().toUpperCase();
        if (sessionId == null || sessionId.isBlank() || sessionId.length() > 64
                || !List.of("red", "green", "yellow", "blue")
                        .contains(selectedColor)
                || !List.of("CLASSIC", "FIRST_KILL").contains(gameMode)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A valid game session, color, and game mode are required.");
        }
        Instant now = Instant.now();
        if (invitationRepository.existsByRequesterIdAndTargetIdAndStatusAndExpiresAtAfter(
                    requesterId, friendId, BuddyGameInvitation.Status.PENDING, now)
                || invitationRepository.existsByRequesterIdAndTargetIdAndStatusAndExpiresAtAfter(
                    friendId, requesterId, BuddyGameInvitation.Status.PENDING, now)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "A buddy game request is already pending.");
        }

        BuddyGameInvitation invitation = invitationRepository.save(
                new BuddyGameInvitation(requesterId, friendId, entryFee,
                        sessionId, selectedColor, gameMode));
        return Map.of("id", invitation.getId().toString(),
                "status", invitation.getStatus().name(),
                "expiresAt", invitation.getExpiresAt().toString());
    }

    @GetMapping("/game-invites/incoming")
    @Transactional(readOnly = true)
    public Map<String, Object> incoming(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        Instant now = Instant.now();
        boolean inGame = matchmakingService.isPlayerInActiveRoom(playerId);
        List<Map<String, Object>> entries = new ArrayList<>();
        for (BuddyGameInvitation invitation : invitationRepository
                .findAllByTargetIdAndStatusAndExpiresAtAfterOrderByCreatedAtAsc(
                        playerId, BuddyGameInvitation.Status.PENDING, now)) {
            PlayerProfile requester = profileRepository
                    .findByUserId(invitation.getRequesterId()).orElse(null);
            Map<String, Object> entry = new LinkedHashMap<>();
            entry.put("id", invitation.getId().toString());
            entry.put("playerId", invitation.getRequesterId().toString());
            entry.put("displayName", requester == null
                    ? "Buddy" : requester.getDisplayName());
            entry.put("entryFee", invitation.getEntryFee());
            entry.put("requesterColor", invitation.getRequesterColor());
            entry.put("gameMode", invitation.getGameMode());
            entry.put("expiresAt", invitation.getExpiresAt().toString());
            entry.put("inGame", inGame);
            entries.add(entry);
        }
        return Map.of("entries", entries);
    }

    @PostMapping("/game-invites/{inviteId}/accept")
    @Transactional
    public Map<String, Object> accept(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID inviteId,
            @RequestBody Map<String, String> body) {
        UUID targetId = PlayerIdResolver.resolve(headerPlayerId);
        BuddyGameInvitation invitation = invitationRepository.findByIdForUpdate(inviteId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Game request not found."));
        if (!invitation.getTargetId().equals(targetId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "This game request belongs to another player.");
        }
        if (invitation.getStatus() == BuddyGameInvitation.Status.ACCEPTED) {
            MatchmakingResponseDto existingMatch = matchmakingService.responseForBuddyRoom(
                    invitation.getRoomId(), targetId);
            if (existingMatch != null) {
                return Map.of("id", invitation.getId().toString(),
                        "status", invitation.getStatus().name(), "match", existingMatch);
            }
        }
        if (invitation.getStatus() != BuddyGameInvitation.Status.PENDING
                || invitation.getExpiresAt().isBefore(Instant.now())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "This game request is no longer available.");
        }
        requireAcceptedBuddies(invitation.getRequesterId(), targetId);

        String targetSessionId = text(body.get("sessionId"));
        if (targetSessionId == null || targetSessionId.isBlank()
                || targetSessionId.length() > 64) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A valid game session is required.");
        }
        PlayerProfile requester = profileRepository.findByUserId(invitation.getRequesterId())
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Buddy profile not found."));
        PlayerProfile target = profileRepository.findByUserId(targetId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Player profile not found."));

        matchmakingService.leaveActiveRoomsForBuddyGame(invitation.getRequesterId(), targetId);
        MatchmakingResponseDto requesterMatch = matchmakingService.createBuddyRoom(
                invitation.getRequesterId(), requester,
                invitation.getRequesterSessionId(), invitation.getRequesterColor(),
                targetId, target, targetSessionId, invitation.getEntryFee(),
                invitation.getGameMode());
        MatchmakingResponseDto targetMatch = matchmakingService.responseForBuddyRoom(
                requesterMatch.getRoomId(), targetId);
        if (targetMatch == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Could not prepare the buddy game.");
        }
        invitation.accept(targetSessionId,
                oppositeColor(invitation.getRequesterColor()),
                requesterMatch.getRoomId());
        invitationRepository.save(invitation);
        return Map.of("id", invitation.getId().toString(),
                "status", invitation.getStatus().name(), "match", targetMatch);
    }

    @PostMapping("/game-invites/{inviteId}/decline")
    @Transactional
    public Map<String, Object> decline(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID inviteId,
            @RequestBody Map<String, String> body) {
        UUID targetId = PlayerIdResolver.resolve(headerPlayerId);
        BuddyGameInvitation invitation = invitationRepository.findByIdForUpdate(inviteId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Game request not found."));
        if (!invitation.getTargetId().equals(targetId)
                || invitation.getStatus() != BuddyGameInvitation.Status.PENDING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "This game request is no longer available.");
        }
        String reason = body == null ? null : text(body.get("reason"));
        reason = reason == null ? "" : reason.trim();
        if (reason.isEmpty() || reason.length() > 500) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Write a short reason for declining (up to 500 characters).");
        }
        invitation.decline(reason);
        invitationRepository.save(invitation);
        return Map.of("id", invitation.getId().toString(), "status", "DECLINED");
    }

    @DeleteMapping("/game-invites/{inviteId}")
    @Transactional
    public Map<String, Object> cancel(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable UUID inviteId) {
        UUID requesterId = PlayerIdResolver.resolve(headerPlayerId);
        BuddyGameInvitation invitation = invitationRepository.findByIdForUpdate(inviteId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Game request not found."));
        if (!invitation.getRequesterId().equals(requesterId)
                || invitation.getStatus() != BuddyGameInvitation.Status.PENDING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "This game request can no longer be cancelled.");
        }
        invitation.cancel();
        invitationRepository.save(invitation);
        return Map.of("id", invitation.getId().toString(), "status", "CANCELLED");
    }

    @GetMapping("/game-invites/outgoing")
    @Transactional(readOnly = true)
    public Map<String, Object> outgoing(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID requesterId = PlayerIdResolver.resolve(headerPlayerId);
        List<Map<String, Object>> entries = new ArrayList<>();
        for (BuddyGameInvitation invitation : invitationRepository
                .findByRequesterIdOrderByCreatedAtDesc(requesterId, PageRequest.of(0, 20))) {
            Map<String, Object> entry = new LinkedHashMap<>();
            entry.put("id", invitation.getId().toString());
            entry.put("targetId", invitation.getTargetId().toString());
            String status = invitation.getStatus().name();
            if (invitation.getStatus() == BuddyGameInvitation.Status.PENDING
                    && invitation.getExpiresAt().isBefore(Instant.now())) {
                status = "EXPIRED";
            }
            entry.put("status", status);
            entry.put("entryFee", invitation.getEntryFee());
            entry.put("gameMode", invitation.getGameMode());
            if (invitation.getStatus() == BuddyGameInvitation.Status.DECLINED) {
                entry.put("declineReason", invitation.getDeclineReason());
            }
            if (invitation.getStatus() == BuddyGameInvitation.Status.ACCEPTED) {
                entry.put("match", matchmakingService.responseForBuddyRoom(
                        invitation.getRoomId(), requesterId));
            }
            entries.add(entry);
        }
        return Map.of("entries", entries);
    }

    private void requireAcceptedBuddies(UUID first, UUID second) {
        boolean accepted = friendshipRepository.findByRequesterIdAndAddresseeId(first, second)
                .or(() -> friendshipRepository.findByRequesterIdAndAddresseeId(second, first))
                .map(friendship -> friendship.getStatus() == Friendship.Status.ACCEPTED)
                .orElse(false);
        if (!accepted) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Buddy game requests are available to accepted buddies only.");
        }
    }

    private static String oppositeColor(String color) {
        return switch (color) {
            case "red" -> "yellow";
            case "green" -> "blue";
            case "yellow" -> "red";
            default -> "green";
        };
    }

    private static String text(Object value) {
        return value == null ? null : value.toString();
    }
}
