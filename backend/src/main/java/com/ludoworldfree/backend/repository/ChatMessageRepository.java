package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.ChatMessage;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.time.Instant;
import java.util.UUID;

public interface ChatMessageRepository extends JpaRepository<ChatMessage, UUID> {
    @Query("""
            select m from ChatMessage m
            where (m.senderId = :playerId and m.recipientId = :friendId)
               or (m.senderId = :friendId and m.recipientId = :playerId)
            order by m.createdAt desc
            """)
    List<ChatMessage> findConversation(@Param("playerId") UUID playerId,
                                       @Param("friendId") UUID friendId,
                                       Pageable pageable);

    List<ChatMessage> findByRecipientIdAndCreatedAtAfterOrderByCreatedAtAsc(
            UUID recipientId, Instant createdAt, Pageable pageable);
}
