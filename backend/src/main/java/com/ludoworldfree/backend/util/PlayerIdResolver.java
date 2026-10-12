package com.ludoworldfree.backend.util;

import java.util.UUID;

public class PlayerIdResolver {

    public static UUID resolve(String headerPlayerId) {
        if (headerPlayerId != null && !headerPlayerId.isBlank()) {
            try {
                return UUID.fromString(headerPlayerId);
            } catch (Exception e) {
                return UUID.nameUUIDFromBytes(headerPlayerId.getBytes());
            }
        }
        return UUID.randomUUID();
    }
}
