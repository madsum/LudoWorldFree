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
    @Query(value = """
            SELECT t.* FROM matchmaking_tickets t
            WHERE t.entry_fee = :entryFee
              AND t.player_count = :playerCount
              AND t.game_mode = :gameMode
              AND t.session_id IS NOT NULL
              AND t.last_seen_at >= :activeAfter
              AND t.player_id <> :playerId
              AND NOT EXISTS (
                  SELECT 1 FROM online_match_rooms r
                  WHERE (r.player_a_id = t.player_id OR r.player_b_id = t.player_id
                      OR r.player_c_id = t.player_id OR r.player_d_id = t.player_id)
                    AND r.status IN (:matchedStatus, :readyStatus)
              )
            ORDER BY t.queued_at ASC
            LIMIT :candidateLimit
            FOR UPDATE OF t SKIP LOCKED
            """, nativeQuery = true)
    List<MatchmakingTicket> findWaitingCandidateForUpdate(
            @Param("entryFee") long entryFee,
            @Param("playerCount") int playerCount,
            @Param("gameMode") String gameMode,
            @Param("activeAfter") Instant activeAfter,
            @Param("playerId") UUID playerId,
            @Param("matchedStatus") String matchedStatus,
            @Param("readyStatus") String readyStatus,
            @Param("candidateLimit") int candidateLimit);

    @Query("select t from MatchmakingTicket t where t.entryFee = :entryFee and t.playerCount = :playerCount and t.gameMode = :gameMode and t.sessionId is not null and t.lastSeenAt >= :activeAfter and t.playerId <> :playerId "
            + "and not exists (select r.roomId from OnlineMatchRoom r where "
            + "(r.playerAId = t.playerId or r.playerBId = t.playerId or r.playerCId = t.playerId or r.playerDId = t.playerId) "
            + "and r.status in :activeStatuses) order by t.queuedAt asc")
    List<MatchmakingTicket> findWaitingCandidatePortable(
            @Param("entryFee") long entryFee,
            @Param("playerCount") int playerCount,
            @Param("gameMode") String gameMode,
            @Param("activeAfter") Instant activeAfter,
            @Param("playerId") UUID playerId,
            @Param("activeStatuses") List<OnlineMatchRoom.Status> activeStatuses,
            Pageable pageable);

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
