package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.PlayerProfile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface PlayerProfileRepository extends JpaRepository<PlayerProfile, UUID> {
    Optional<PlayerProfile> findByUserId(UUID userId);
    Optional<PlayerProfile> findByDisplayName(String displayName);
    boolean existsByDisplayName(String displayName);
}
