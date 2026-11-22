package com.ludoworldfree.backend.dto;

import java.util.UUID;

public record FriendPlayRoomSeatDto(
        UUID playerId,
        String displayName,
        String avatarUrl,
        String country,
        String countryFlag,
        String selectedColor,
        String sessionId,
        String tokenSkinId) {}
