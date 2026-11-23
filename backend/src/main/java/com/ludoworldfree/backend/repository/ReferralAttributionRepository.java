package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.ReferralAttribution;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ReferralAttributionRepository extends JpaRepository<ReferralAttribution, UUID> {
    long countByReferrerPlayerId(UUID referrerPlayerId);
}
