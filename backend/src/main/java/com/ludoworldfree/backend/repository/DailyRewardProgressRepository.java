package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.DailyRewardProgress;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface DailyRewardProgressRepository extends JpaRepository<DailyRewardProgress, UUID> {
    Optional<DailyRewardProgress> findByPlayerId(UUID playerId);
}
