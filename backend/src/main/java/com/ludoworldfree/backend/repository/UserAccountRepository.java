package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.UserAccount;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface UserAccountRepository extends JpaRepository<UserAccount, UUID> {
    Optional<UserAccount> findByEmail(String email);
    Optional<UserAccount> findByAuthProviderAndProviderId(String authProvider, String providerId);
    boolean existsByEmail(String email);
}
