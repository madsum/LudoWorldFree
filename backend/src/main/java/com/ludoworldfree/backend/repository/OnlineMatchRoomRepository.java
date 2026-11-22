package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.OnlineMatchRoom;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Collection;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

public interface OnlineMatchRoomRepository extends JpaRepository<OnlineMatchRoom, String> {
    List<OnlineMatchRoom> findAllByRoomIdIn(Collection<String> roomIds);
    @Query("select r from OnlineMatchRoom r where (r.playerAId = :playerId or r.playerBId = :playerId or r.playerCId = :playerId or r.playerDId = :playerId) and r.status in :statuses order by r.createdAt desc")
    List<OnlineMatchRoom> findActiveForPlayer(@Param("playerId") UUID playerId,
                                             @Param("statuses") List<OnlineMatchRoom.Status> statuses);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from OnlineMatchRoom r where (r.playerAId = :playerId or r.playerBId = :playerId or r.playerCId = :playerId or r.playerDId = :playerId) and r.status in :statuses order by r.createdAt desc")
    List<OnlineMatchRoom> findActiveForPlayerForUpdate(
            @Param("playerId") UUID playerId,
            @Param("statuses") List<OnlineMatchRoom.Status> statuses);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from OnlineMatchRoom r where r.roomId = :roomId")
    Optional<OnlineMatchRoom> findForUpdate(@Param("roomId") String roomId);
}
