package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.Friendship;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.time.Instant;
import org.springframework.data.domain.Pageable;

public interface FriendshipRepository extends JpaRepository<Friendship, UUID> {
    List<Friendship> findAllByRequesterIdOrAddresseeId(UUID requesterId, UUID addresseeId);
    Optional<Friendship> findByRequesterIdAndAddresseeId(UUID requesterId, UUID addresseeId);
    List<Friendship> findByRequesterIdAndUpdatedAtAfterOrderByUpdatedAtAsc(
            UUID requesterId, Instant updatedAt, Pageable pageable);
}
