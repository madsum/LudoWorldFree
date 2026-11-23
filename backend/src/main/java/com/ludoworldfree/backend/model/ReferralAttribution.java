package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "referral_attributions")
public class ReferralAttribution {
    @Id
    private UUID referredPlayerId;

    @Column(nullable = false)
    private UUID referrerPlayerId;

    @Column(nullable = false, length = 16)
    private String referralCode;

    @Column(nullable = false)
    private Instant createdAt = Instant.now();

    protected ReferralAttribution() {}

    public ReferralAttribution(UUID referredPlayerId, UUID referrerPlayerId, String referralCode) {
        this.referredPlayerId = referredPlayerId;
        this.referrerPlayerId = referrerPlayerId;
        this.referralCode = referralCode;
    }
}
