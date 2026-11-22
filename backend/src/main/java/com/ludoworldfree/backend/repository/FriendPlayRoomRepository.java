package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.FriendPlayRoom;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FriendPlayRoomRepository extends JpaRepository<FriendPlayRoom, String> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from FriendPlayRoom r where r.roomCode = :code")
    Optional<FriendPlayRoom> findByCodeForUpdate(@Param("code") String code);

    Optional<FriendPlayRoom> findByRoomCode(String code);

    List<FriendPlayRoom> findAllByStatusAndExpiresAtBefore(String status, Instant expiresAt);
}
