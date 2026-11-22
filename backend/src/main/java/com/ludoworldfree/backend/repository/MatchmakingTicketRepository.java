package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.MatchmakingTicket;
import com.ludoworldfree.backend.model.OnlineMatchRoom;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.time.Instant;

public interface MatchmakingTicketRepository extends JpaRepository<MatchmakingTicket, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from MatchmakingTicket t where t.entryFee = :entryFee and t.playerCount = :playerCount and t.gameMode = :gameMode and t.sessionId is not null and t.lastSeenAt >= :activeAfter and t.playerId <> :playerId "
            + "and not exists (select r.roomId from OnlineMatchRoom r where "
            + "(r.playerAId = t.playerId or r.playerBId = t.playerId or r.playerCId = t.playerId or r.playerDId = t.playerId) "
            + "and r.status in :activeStatuses) order by t.queuedAt asc")
    List<MatchmakingTicket> findWaitingCandidateForUpdate(
            @Param("entryFee") long entryFee,
            @Param("playerCount") int playerCount,
            @Param("gameMode") String gameMode,
            @Param("activeAfter") Instant activeAfter,
            @Param("playerId") UUID playerId,
            @Param("activeStatuses") List<OnlineMatchRoom.Status> activeStatuses,
            Pageable pageable);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from MatchmakingTicket t where t.entryFee < :entryFee and t.playerCount = :playerCount and t.gameMode = :gameMode and t.sessionId is not null and t.lastSeenAt >= :activeAfter and t.playerId <> :playerId "
            + "and not exists (select r.roomId from OnlineMatchRoom r where "
            + "(r.playerAId = t.playerId or r.playerBId = t.playerId or r.playerCId = t.playerId or r.playerDId = t.playerId) "
            + "and r.status in :activeStatuses) order by t.entryFee desc, t.queuedAt asc")
    List<MatchmakingTicket> findLowerStakeCandidatesForUpdate(
            @Param("entryFee") long entryFee,
            @Param("playerCount") int playerCount,
            @Param("gameMode") String gameMode,
            @Param("activeAfter") Instant activeAfter,
            @Param("playerId") UUID playerId,
            @Param("activeStatuses") List<OnlineMatchRoom.Status> activeStatuses,
            Pageable pageable);

    // Status polling can overlap the queue-join request for the same player.
    // Lock the ticket before touching last_seen_at so Hibernate doesn't flush
    // a stale update after another request has already changed/deleted it.
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from MatchmakingTicket t where t.playerId = :playerId")
    Optional<MatchmakingTicket> findByPlayerIdForUpdate(@Param("playerId") UUID playerId);

    @Modifying(flushAutomatically = true)
    @Query("update MatchmakingTicket t set t.lastSeenAt = :lastSeenAt where t.playerId = :playerId")
    int touchByPlayerId(@Param("playerId") UUID playerId,
                        @Param("lastSeenAt") Instant lastSeenAt);

    int deleteByLastSeenAtBefore(Instant expiredBefore);
}
