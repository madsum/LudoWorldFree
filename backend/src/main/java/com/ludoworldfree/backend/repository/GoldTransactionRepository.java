package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.GoldTransaction;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface GoldTransactionRepository extends JpaRepository<GoldTransaction, UUID> {
    List<GoldTransaction> findByPlayerIdOrderByCreatedAtDesc(UUID playerId);
    Page<GoldTransaction> findByPlayerId(UUID playerId, Pageable pageable);
    List<GoldTransaction> findByPlayerIdAndTransactionType(UUID playerId, GoldTransaction.TransactionType transactionType);
}
