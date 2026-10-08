package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.RewardEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface RewardEventRepository extends JpaRepository<RewardEvent, UUID> {
    Optional<RewardEvent> findByProviderAndProviderRewardId(String provider, String providerRewardId);
    boolean existsByProviderAndProviderRewardId(String provider, String providerRewardId);
}
