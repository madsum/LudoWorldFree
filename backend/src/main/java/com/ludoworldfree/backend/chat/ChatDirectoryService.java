package com.ludoworldfree.backend.chat;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class ChatDirectoryService {
    public record ProfileUpdate(String displayName, String avatarUrl) {}

    private final JdbcTemplate jdbc;
    private final ChatPresenceService presence;

    public ChatDirectoryService(JdbcTemplate jdbc, ChatPresenceService presence) {
        this.jdbc = jdbc;
        this.presence = presence;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> profile(UUID userId) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT user_id AS "userId", display_name AS "displayName",
                       avatar_url AS "avatarUrl", country, country_flag AS "countryFlag"
                FROM player_profiles WHERE user_id = ?
                """, userId);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Player profile not found.");
        return rows.getFirst();
    }

    @Transactional
    public Map<String, Object> updateProfile(UUID userId, ProfileUpdate update) {
        if (update == null) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "A profile update is required.");
        String displayName = update.displayName() == null ? null : update.displayName().trim();
        String avatarUrl = update.avatarUrl() == null ? null : update.avatarUrl().trim();
        if (displayName != null && (displayName.isEmpty() || displayName.length() > 60)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Display names must contain 1 to 60 characters.");
        }
        if (avatarUrl != null && avatarUrl.length() > 500) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Avatar URL is too long.");
        }
        int changed = jdbc.update("""
                UPDATE player_profiles
                SET display_name = COALESCE(?, display_name),
                    avatar_url = COALESCE(?, avatar_url), updated_at = CURRENT_TIMESTAMP
                WHERE user_id = ?
                """, displayName, avatarUrl, userId);
        if (changed == 0) throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Player profile not found.");
        return profile(userId);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> contacts(UUID userId, String search) {
        String pattern = search == null || search.isBlank()
                ? "%" : "%" + search.trim() + "%";
        List<Map<String, Object>> contacts = jdbc.query("""
                SELECT p.user_id AS "userId", p.display_name AS "displayName",
                       p.avatar_url AS "avatarUrl", p.country, p.country_flag AS "countryFlag"
                FROM player_profiles p
                JOIN friendships f ON f.status = 'ACCEPTED'
                  AND ((f.requester_id = ? AND f.addressee_id = p.user_id)
                    OR (f.addressee_id = ? AND f.requester_id = p.user_id))
                WHERE p.user_id <> ? AND p.display_name ILIKE ?
                ORDER BY p.display_name, p.user_id
                LIMIT 50
                """, (rs, rowNum) -> {
                    Map<String, Object> contact = new LinkedHashMap<>();
                    UUID contactId = rs.getObject("userId", UUID.class);
                    contact.put("userId", contactId.toString());
                    contact.put("displayName", rs.getString("displayName"));
                    contact.put("avatarUrl", rs.getString("avatarUrl"));
                    contact.put("country", rs.getString("country"));
                    contact.put("countryFlag", rs.getString("countryFlag"));
                    contact.put("online", presence.isOnline(contactId));
                    contact.put("lastSeenAt", presence.lastSeen(contactId) == null
                            ? null : presence.lastSeen(contactId).toString());
                    return contact;
                }, userId, userId, userId, pattern);
        return contacts;
    }
}
