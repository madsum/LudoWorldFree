package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.PlayerWallet;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface PlayerWalletRepository extends JpaRepository<PlayerWallet, UUID> {
    Optional<PlayerWallet> findByPlayerId(UUID playerId);
}
