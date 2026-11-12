package com.ludoworldfree.backend.util;

import java.util.UUID;
import java.nio.charset.StandardCharsets;

public class PlayerIdResolver {

    public static UUID resolve(String headerPlayerId) {
        if (headerPlayerId != null && !headerPlayerId.isBlank()) {
            try {
                return UUID.fromString(headerPlayerId);
            } catch (Exception e) {
                return UUID.nameUUIDFromBytes(headerPlayerId.getBytes(StandardCharsets.UTF_8));
            }
        }
        return UUID.randomUUID();
    }
}
