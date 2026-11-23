package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "referral_codes")
public class ReferralCode {
    @Id
    @Column(length = 16)
    private String code;

    @Column(nullable = false, unique = true)
    private UUID referrerPlayerId;

    @Column(nullable = false)
    private Instant createdAt = Instant.now();

    protected ReferralCode() {}

    public ReferralCode(String code, UUID referrerPlayerId) {
        this.code = code;
        this.referrerPlayerId = referrerPlayerId;
    }

    public String getCode() { return code; }
    public UUID getReferrerPlayerId() { return referrerPlayerId; }
}
