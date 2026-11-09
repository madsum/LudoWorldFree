package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.MatchmakingTicket;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface MatchmakingTicketRepository extends JpaRepository<MatchmakingTicket, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from MatchmakingTicket t where t.entryFee = :entryFee and t.playerCount = :playerCount and t.playerId <> :playerId order by t.queuedAt asc")
    List<MatchmakingTicket> findWaitingCandidateForUpdate(
            @Param("entryFee") long entryFee,
            @Param("playerCount") int playerCount,
            @Param("playerId") UUID playerId,
            Pageable pageable);

    Optional<MatchmakingTicket> findByPlayerId(UUID playerId);
}
