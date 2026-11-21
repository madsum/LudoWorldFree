package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.BuddyGameInvitation;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface BuddyGameInvitationRepository
        extends JpaRepository<BuddyGameInvitation, UUID> {
    List<BuddyGameInvitation> findAllByTargetIdAndStatusAndExpiresAtAfterOrderByCreatedAtAsc(
            UUID targetId, BuddyGameInvitation.Status status, Instant now);

    List<BuddyGameInvitation> findByRequesterIdOrderByCreatedAtDesc(
            UUID requesterId, Pageable pageable);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select i from BuddyGameInvitation i where i.id = :id")
    Optional<BuddyGameInvitation> findByIdForUpdate(@Param("id") UUID id);

    boolean existsByRequesterIdAndTargetIdAndStatusAndExpiresAtAfter(
            UUID requesterId, UUID targetId, BuddyGameInvitation.Status status,
            Instant now);
}
