package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.DailyGoal;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface DailyGoalRepository extends JpaRepository<DailyGoal, UUID> {
    List<DailyGoal> findAllByPlayerIdAndGoalDateOrderByGoalType(UUID playerId, LocalDate goalDate);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select g from DailyGoal g where g.playerId = :playerId and g.goalDate = :goalDate and g.goalType = :goalType")
    Optional<DailyGoal> findForUpdate(@Param("playerId") UUID playerId,
                                     @Param("goalDate") LocalDate goalDate,
                                     @Param("goalType") String goalType);
}
