package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.MatchmakingTicket;
import com.ludoworldfree.backend.model.OnlineMatchRoom;
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
    @Query("select t from MatchmakingTicket t where t.entryFee = :entryFee and t.playerCount = :playerCount and t.playerId <> :playerId "
            + "and not exists (select r.roomId from OnlineMatchRoom r where "
            + "(r.playerAId = t.playerId or r.playerBId = t.playerId or r.playerCId = t.playerId or r.playerDId = t.playerId) "
            + "and r.status in :activeStatuses) order by t.queuedAt asc")
    List<MatchmakingTicket> findWaitingCandidateForUpdate(
            @Param("entryFee") long entryFee,
            @Param("playerCount") int playerCount,
            @Param("playerId") UUID playerId,
            @Param("activeStatuses") List<OnlineMatchRoom.Status> activeStatuses,
            Pageable pageable);

    Optional<MatchmakingTicket> findByPlayerId(UUID playerId);
}
