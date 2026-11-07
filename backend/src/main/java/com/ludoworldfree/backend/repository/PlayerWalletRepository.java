package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.PlayerWallet;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

@Repository
public interface PlayerWalletRepository extends JpaRepository<PlayerWallet, UUID> {
    Optional<PlayerWallet> findByPlayerId(UUID playerId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select w from PlayerWallet w where w.playerId = :playerId")
    Optional<PlayerWallet> findByPlayerIdForUpdate(@Param("playerId") UUID playerId);
}
