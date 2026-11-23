package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.ReferralCode;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ReferralCodeRepository extends JpaRepository<ReferralCode, String> {
    Optional<ReferralCode> findByReferrerPlayerId(UUID playerId);
}
