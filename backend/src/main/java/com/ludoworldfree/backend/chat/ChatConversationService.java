package com.ludoworldfree.backend.chat;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class ChatConversationService {
    private final JdbcTemplate jdbc;

    public ChatConversationService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Transactional
    public UUID createDirect(UUID creatorId, UUID otherUserId) {
        if (creatorId.equals(otherUserId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A direct conversation needs another user.");
        }
        requireAccount(creatorId);
        requireAccount(otherUserId);
        requireAcceptedFriendship(creatorId, otherUserId);
        String first = creatorId.toString().compareTo(otherUserId.toString()) < 0
                ? creatorId.toString() : otherUserId.toString();
        String second = first.equals(creatorId.toString())
                ? otherUserId.toString() : creatorId.toString();
        String directKey = first + ":" + second;
        UUID conversationId = jdbc.queryForObject("""
                INSERT INTO conversations (id, conversation_type, direct_key, created_by)
                VALUES (?, 'DIRECT', ?, ?)
                ON CONFLICT (direct_key) DO UPDATE
                SET updated_at = conversations.updated_at
                RETURNING id
                """, UUID.class, UUID.randomUUID(), directKey, creatorId);
        addParticipant(conversationId, creatorId, "OWNER");
        addParticipant(conversationId, otherUserId, "MEMBER");
        return conversationId;
    }

    @Transactional
    public UUID createGroup(UUID creatorId, String title, List<UUID> requestedMembers) {
        String normalizedTitle = title == null ? "" : title.trim();
        if (normalizedTitle.isEmpty() || normalizedTitle.length() > 120) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Group names must contain 1 to 120 characters.");
        }
        if (requestedMembers == null || requestedMembers.isEmpty()
                || requestedMembers.size() > 99) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A group must have between 2 and 100 participants.");
        }
        requireAccount(creatorId);
        List<UUID> members = new ArrayList<>();
        members.add(creatorId);
        for (UUID memberId : requestedMembers) {
            if (memberId == null || memberId.equals(creatorId) || members.contains(memberId)) continue;
            requireAccount(memberId);
            requireAcceptedFriendship(creatorId, memberId);
            members.add(memberId);
        }
        if (members.size() < 3) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose at least two friends for a group chat.");
        }
        UUID conversationId = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO conversations (id, conversation_type, title, created_by)
                VALUES (?, 'GROUP', ?, ?)
                """, conversationId, normalizedTitle, creatorId);
        for (UUID memberId : members) {
            addParticipant(conversationId, memberId,
                    memberId.equals(creatorId) ? "OWNER" : "MEMBER");
        }
        return conversationId;
    }

    @Transactional(readOnly = true)
    public void requireParticipant(UUID conversationId, UUID userId) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM conversation_participants
                WHERE conversation_id = ? AND user_id = ?
                """, Integer.class, conversationId, userId);
        if (count == null || count != 1) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "You are not a participant in this conversation.");
        }
    }

    @Transactional(readOnly = true)
    public List<UUID> participantIds(UUID conversationId) {
        return jdbc.query("""
                SELECT user_id FROM conversation_participants
                WHERE conversation_id = ? ORDER BY joined_at, user_id
                """, (rs, rowNum) -> rs.getObject(1, UUID.class), conversationId);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> listForUser(UUID userId) {
        return jdbc.queryForList("""
                SELECT c.id AS "conversationId", c.conversation_type AS "type",
                       c.title, c.last_sequence AS "lastSequence",
                       cp.last_read_sequence AS "lastReadSequence",
                       c.updated_at AS "updatedAt"
                FROM conversation_participants cp
                JOIN conversations c ON c.id = cp.conversation_id
                WHERE cp.user_id = ?
                ORDER BY c.updated_at DESC, c.id
                LIMIT 200
                """, userId);
    }

    private void addParticipant(UUID conversationId, UUID userId, String role) {
        jdbc.update("""
                INSERT INTO conversation_participants (conversation_id, user_id, role)
                VALUES (?, ?, ?)
                ON CONFLICT (conversation_id, user_id) DO NOTHING
                """, conversationId, userId, role);
    }

    private void requireAccount(UUID userId) {
        try {
            jdbc.queryForObject("SELECT id FROM user_accounts WHERE id = ?", UUID.class, userId);
        } catch (EmptyResultDataAccessException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Player account not found.");
        }
    }

    private void requireAcceptedFriendship(UUID first, UUID second) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM friendships
                WHERE status = 'ACCEPTED'
                  AND ((requester_id = ? AND addressee_id = ?)
                    OR (requester_id = ? AND addressee_id = ?))
                """, Integer.class, first, second, second, first);
        if (count == null || count == 0) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Chat conversations can only be created with accepted friends.");
        }
    }
}
