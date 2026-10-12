package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.model.PlayerWallet;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import com.ludoworldfree.backend.repository.PlayerWalletRepository;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.LinkedHashMap;
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
    public ResponseEntity<?> getPlayerProfile(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID userId = PlayerIdResolver.resolve(headerPlayerId);
        PlayerProfile profile = profileRepository.findByUserId(userId)
                .orElseGet(() -> profileRepository.save(new PlayerProfile(
                        userId, "Guest Player", "avatar_crown", "World", "🌐")));
        PlayerWallet wallet = walletRepository.findByPlayerId(userId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(userId, 2000L)));

        return ResponseEntity.ok(profileResponse(userId, profile, wallet));
    }

    @GetMapping("/username")
    public ResponseEntity<?> getPlayerByUsername(
            @RequestParam String username) {

        PlayerProfile profile = profileRepository.findByDisplayName(username)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Player not found"));

        PlayerWallet wallet = walletRepository.findByPlayerId(profile.getUserId())
                .orElseThrow();

        return ResponseEntity.ok(profileResponse(
                profile.getUserId(), profile, wallet));
    }

    @PutMapping("/profile")
    public ResponseEntity<?> savePlayerProfile(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestBody Map<String, Object> payload) {
        UUID userId = PlayerIdResolver.resolve(headerPlayerId);
        PlayerProfile profile = profileRepository.findByUserId(userId)
                .orElseGet(() -> new PlayerProfile(userId, "Guest Player", "avatar_crown", "World", "🌐"));

        setString(payload, "displayName", profile::setDisplayName);
        setString(payload, "avatarUrl", profile::setAvatarUrl);
        setString(payload, "country", profile::setCountry);
        setString(payload, "countryFlag", profile::setCountryFlag);

        if (payload.containsKey("preferredGameType")) {
            String preferredStr = (String) payload.get("preferredGameType");
            if (preferredStr != null) {
                try {
                    profile.setPreferredGameType(PlayerProfile.GameType.valueOf(preferredStr.toUpperCase()));
                } catch (Exception ignored) {}
            }
        }

        profile = profileRepository.save(profile);

        PlayerWallet wallet = walletRepository.findByPlayerId(userId).orElse(null);
        if (wallet == null) {
            wallet = new PlayerWallet(userId, longValue(payload.get("goldCoins"), 2000L));
        } else if (payload.containsKey("goldCoins")) {
            wallet.setBalance(Math.max(0, longValue(payload.get("goldCoins"), wallet.getBalance())));
        }
        wallet = walletRepository.save(wallet);

        return ResponseEntity.ok(profileResponse(userId, profile, wallet));
    }

    @PostMapping("/game-session/complete")
    public ResponseEntity<?> completeGameSession(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestBody Map<String, Object> payload) {
        UUID userId = PlayerIdResolver.resolve(headerPlayerId);
        PlayerProfile profile = profileRepository.findByUserId(userId)
                .orElseGet(() -> profileRepository.save(new PlayerProfile(userId, "Guest Player", "avatar_crown", "World", "🌐")));

        String gameTypeStr = (String) payload.getOrDefault("gameType", "CLASSIC");
        try {
            PlayerProfile.GameType gameType = PlayerProfile.GameType.valueOf(gameTypeStr.toUpperCase());
            profile.recordGameSession(gameType);
            profile = profileRepository.save(profile);
        } catch (Exception ignored) {}

        PlayerWallet wallet = walletRepository.findByPlayerId(userId)
                .orElseGet(() -> walletRepository.save(new PlayerWallet(userId, 2000L)));

        return ResponseEntity.ok(profileResponse(userId, profile, wallet));
    }

    private static void setString(Map<String, Object> payload, String key,
                                  java.util.function.Consumer<String> setter) {
        Object value = payload.get(key);
        if (value instanceof String string && !string.isBlank()) {
            setter.accept(string);
        }
    }

    private static long longValue(Object value, long fallback) {
        return value instanceof Number number ? number.longValue() : fallback;
    }

    private static Map<String, Object> profileResponse(UUID userId, PlayerProfile profile, PlayerWallet wallet) {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("playerId", userId.toString());
        response.put("displayName", profile.getDisplayName());
        response.put("avatarUrl", profile.getAvatarUrl());
        response.put("country", profile.getCountry());
        response.put("countryFlag", profile.getCountryFlag());
        response.put("preferredGameType", profile.getPreferredGameType().name());
        response.put("mostPlayedGameType", profile.getMostPlayedGameType().name());
        response.put("classicPlayCount", profile.getClassicPlayCount());
        response.put("quickPlayCount", profile.getQuickPlayCount());
        response.put("teamUpPlayCount", profile.getTeamUpPlayCount());
        response.put("computerPlayCount", profile.getComputerPlayCount());
        response.put("passNPlayPlayCount", profile.getPassNPlayPlayCount());
        response.put("goldCoins", wallet.getBalance());
        return response;
    }
}
