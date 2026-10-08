package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.model.PlayerWallet;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import com.ludoworldfree.backend.repository.PlayerWalletRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/player")
public class PlayerProfileController {

    private final PlayerProfileRepository profileRepository;
    private final PlayerWalletRepository walletRepository;

    public PlayerProfileController(
            PlayerProfileRepository profileRepository,
            PlayerWalletRepository walletRepository) {
        this.profileRepository = profileRepository;
        this.walletRepository = walletRepository;
    }

    @GetMapping("/profile")
    public ResponseEntity<?> getPlayerProfile(@RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID playerId;
        try {
            playerId = (headerPlayerId != null && !headerPlayerId.isBlank())
                    ? UUID.fromString(headerPlayerId)
                    : UUID.randomUUID();
        } catch (Exception e) {
            playerId = UUID.randomUUID();
        }

        final UUID id = playerId;
        PlayerProfile profile = profileRepository.findById(id)
                .orElseGet(() -> profileRepository.save(new PlayerProfile(id, "Guest Player", "avatar_crown", "Netherlands", "🇳🇱")));

        PlayerWallet wallet = walletRepository.findByPlayerId(id)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(id, 2350)));

        return ResponseEntity.ok(Map.of(
                "playerId", profile.getId(),
                "displayName", profile.getDisplayName(),
                "avatarUrl", profile.getAvatarUrl(),
                "country", profile.getCountry(),
                "countryFlag", profile.getCountryFlag(),
                "goldCoins", wallet.getBalance()
        ));
    }
}
