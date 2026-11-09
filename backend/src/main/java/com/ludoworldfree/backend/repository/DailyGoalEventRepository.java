package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.DailyGoalEvent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface DailyGoalEventRepository extends JpaRepository<DailyGoalEvent, UUID> {
    boolean existsByPlayerIdAndEventId(UUID playerId, String eventId);
}
