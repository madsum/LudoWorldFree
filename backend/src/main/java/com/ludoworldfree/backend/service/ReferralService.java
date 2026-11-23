package com.ludoworldfree.backend.service;

import com.ludoworldfree.backend.model.GoldTransaction;
import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.model.PlayerWallet;
import com.ludoworldfree.backend.model.ReferralAttribution;
import com.ludoworldfree.backend.model.ReferralCode;
import com.ludoworldfree.backend.repository.GoldTransactionRepository;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import com.ludoworldfree.backend.repository.PlayerWalletRepository;
import com.ludoworldfree.backend.repository.ReferralAttributionRepository;
import com.ludoworldfree.backend.repository.ReferralCodeRepository;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ReferralService {
    public static final long REFERRER_REWARD = 10_000L;
    public static final long NEW_PLAYER_REWARD = 1_000L;
    private static final String CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Duration ELIGIBILITY_WINDOW = Duration.ofDays(7);

    private final ReferralCodeRepository codeRepository;
    private final ReferralAttributionRepository attributionRepository;
    private final PlayerProfileRepository profileRepository;
    private final PlayerWalletRepository walletRepository;
    private final GoldTransactionRepository transactionRepository;
    private final JdbcTemplate jdbcTemplate;

    public ReferralService(ReferralCodeRepository codeRepository,
            ReferralAttributionRepository attributionRepository,
            PlayerProfileRepository profileRepository,
            PlayerWalletRepository walletRepository,
            GoldTransactionRepository transactionRepository,
            JdbcTemplate jdbcTemplate) {
        this.codeRepository = codeRepository;
        this.attributionRepository = attributionRepository;
        this.profileRepository = profileRepository;
        this.walletRepository = walletRepository;
        this.transactionRepository = transactionRepository;
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional
    public Map<String, Object> details(UUID playerId) {
        if (!profileRepository.existsByUserId(playerId)) {
            throw new IllegalStateException("Create your player profile before inviting friends.");
        }
        ReferralCode code = codeRepository.findByReferrerPlayerId(playerId)
                .orElseGet(() -> codeRepository.save(new ReferralCode(newCode(), playerId)));
        long successful = attributionRepository.countByReferrerPlayerId(playerId);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("code", code.getCode());
        result.put("successfulReferrals", successful);
        result.put("goldEarned", successful * REFERRER_REWARD);
        result.put("rewardPerReferral", REFERRER_REWARD);
        return result;
    }

    @Transactional
    public Map<String, Object> claim(UUID referredPlayerId, String rawCode) {
        String code = rawCode == null ? "" : rawCode.trim().toUpperCase();
        ReferralCode invite = codeRepository.findById(code).orElse(null);
        if (invite == null) return result(false, false, "This referral link is invalid.", 0, 0);
        if (invite.getReferrerPlayerId().equals(referredPlayerId)) {
            return result(false, false, "You cannot use your own referral link.", 0, 0);
        }

        PlayerProfile profile = profileRepository.findByUserId(referredPlayerId).orElse(null);
        if (profile == null || profile.getCreatedAt() == null
                || profile.getCreatedAt().isBefore(Instant.now().minus(ELIGIBILITY_WINDOW))) {
            return result(false, false, "Referral rewards are for newly installed accounts.", 0, 0);
        }

        var existing = attributionRepository.findById(referredPlayerId);
        if (existing.isPresent()) {
            PlayerWallet wallet = walletRepository.findByPlayerId(referredPlayerId).orElse(null);
            return result(false, true, "Referral already claimed.",
                    wallet == null ? 0 : wallet.getBalance(),
                    attributionRepository.countByReferrerPlayerId(invite.getReferrerPlayerId()));
        }

        int inserted = jdbcTemplate.update("""
                INSERT INTO referral_attributions (referred_player_id, referrer_player_id, referral_code)
                VALUES (?, ?, ?) ON CONFLICT (referred_player_id) DO NOTHING
                """, referredPlayerId, invite.getReferrerPlayerId(), code);
        if (inserted == 0) {
            PlayerWallet wallet = walletRepository.findByPlayerId(referredPlayerId).orElse(null);
            return result(false, true, "Referral already claimed.",
                    wallet == null ? 0 : wallet.getBalance(),
                    attributionRepository.countByReferrerPlayerId(invite.getReferrerPlayerId()));
        }

        UUID referrerPlayerId = invite.getReferrerPlayerId();
        PlayerWallet referredWallet;
        PlayerWallet referrerWallet;
        if (referredPlayerId.compareTo(referrerPlayerId) < 0) {
            referredWallet = lockOrCreateWallet(referredPlayerId);
            referrerWallet = lockOrCreateWallet(referrerPlayerId);
        } else {
            referrerWallet = lockOrCreateWallet(referrerPlayerId);
            referredWallet = lockOrCreateWallet(referredPlayerId);
        }

        credit(referredWallet, NEW_PLAYER_REWARD, "REFERRAL_INSTALLER", code);
        credit(referrerWallet, REFERRER_REWARD, "REFERRAL_INVITER", referredPlayerId.toString());
        walletRepository.save(referredWallet);
        walletRepository.save(referrerWallet);

        return result(true, true, "Referral rewards added.", referredWallet.getBalance(),
                attributionRepository.countByReferrerPlayerId(invite.getReferrerPlayerId()));
    }

    private void credit(PlayerWallet wallet, long amount, String source, String reference) {
        long before = wallet.getBalance();
        wallet.setBalance(before + amount);
        transactionRepository.save(new GoldTransaction(wallet.getPlayerId(),
                GoldTransaction.TransactionType.REFERRAL_BONUS, amount, before,
                wallet.getBalance(), reference, source));
    }

    private PlayerWallet lockOrCreateWallet(UUID playerId) {
        return walletRepository.findByPlayerIdForUpdate(playerId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(playerId, 2_000L)));
    }

    private Map<String, Object> result(boolean success, boolean claimed, String message,
            long balance, long successfulReferrals) {
        return Map.of("success", success, "claimed", claimed, "message", message,
                "balance", balance, "successfulReferrals", successfulReferrals,
                "referrerReward", REFERRER_REWARD, "newPlayerReward", NEW_PLAYER_REWARD);
    }

    private String newCode() {
        for (int attempt = 0; attempt < 5; attempt++) {
            StringBuilder code = new StringBuilder(9);
            for (int i = 0; i < 9; i++) code.append(CODE_ALPHABET.charAt(RANDOM.nextInt(CODE_ALPHABET.length())));
            if (!codeRepository.existsById(code.toString())) return code.toString();
        }
        throw new DataIntegrityViolationException("Could not generate a unique referral code.");
    }
}
