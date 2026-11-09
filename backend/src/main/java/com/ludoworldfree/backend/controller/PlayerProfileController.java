package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.model.PlayerProfile;
import com.ludoworldfree.backend.model.PlayerAvatarImage;
import com.ludoworldfree.backend.model.PlayerWallet;
import com.ludoworldfree.backend.repository.PlayerAvatarImageRepository;
import com.ludoworldfree.backend.repository.PlayerProfileRepository;
import com.ludoworldfree.backend.repository.PlayerWalletRepository;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@RestController
@RequestMapping("/api/v1/player")
public class PlayerProfileController {

    private static final Logger log = LoggerFactory.getLogger(PlayerProfileController.class);

    private final PlayerProfileRepository profileRepository;
    private final PlayerWalletRepository walletRepository;
    private final PlayerAvatarImageRepository avatarImageRepository;

    public PlayerProfileController(
            PlayerProfileRepository profileRepository,
            PlayerWalletRepository walletRepository,
            PlayerAvatarImageRepository avatarImageRepository) {
        this.profileRepository = profileRepository;
        this.walletRepository = walletRepository;
        this.avatarImageRepository = avatarImageRepository;
    }

    private static final long MAX_AVATAR_BYTES = 5L * 1024 * 1024;
    private static final int MAX_AVATAR_DIMENSION = 4096;
    private static final long MAX_AVATAR_PIXELS = 16_777_216L;

    @PostMapping(value = "/profile/avatar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> uploadProfileAvatar(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestPart("file") MultipartFile file) {
        UUID userId = PlayerIdResolver.resolve(headerPlayerId);
        if (file.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Choose an image first.");
        }
        if (file.getSize() > MAX_AVATAR_BYTES) {
            throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE,
                    "Profile images must be 5 MB or smaller.");
        }

        byte[] bytes;
        String contentType;
        try {
            bytes = file.getBytes();
            contentType = validateAvatar(file.getOriginalFilename(), bytes);
        } catch (IOException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "The selected image could not be read.");
        }

        PlayerAvatarImage avatar = avatarImageRepository.findById(userId)
                .orElseGet(() -> new PlayerAvatarImage(userId, contentType, bytes));
        avatar.replace(contentType, bytes);
        avatarImageRepository.save(avatar);

        String avatarUrl = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/v1/player/profile/avatar/{playerId}")
                .buildAndExpand(userId)
                .toUriString();
        PlayerProfile profile = profileRepository.findByUserId(userId)
                .orElseGet(() -> new PlayerProfile(userId, "Guest Player",
                        avatarUrl, "World", "🌐"));
        profile.setAvatarUrl(avatarUrl);
        profileRepository.save(profile);

        return ResponseEntity.ok(Map.of("avatarUrl", avatarUrl));
    }

    @GetMapping("/profile/avatar/{playerId}")
    public ResponseEntity<byte[]> getProfileAvatar(@PathVariable UUID playerId) {
        PlayerAvatarImage avatar = avatarImageRepository.findById(playerId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Profile image not found."));
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(avatar.getContentType()))
                .cacheControl(CacheControl.maxAge(1, TimeUnit.DAYS).cachePublic())
                .header(HttpHeaders.X_CONTENT_TYPE_OPTIONS, "nosniff")
                .body(avatar.getImageData());
    }

    private static String validateAvatar(String filename, byte[] bytes) throws IOException {
        if (bytes.length < 12) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "The selected file is not a valid image.");
        }
        String extension = filename == null || !filename.contains(".")
                ? "" : filename.substring(filename.lastIndexOf('.') + 1).toLowerCase();
        String contentType;
        if (isPng(bytes)) contentType = "image/png";
        else if (isJpeg(bytes)) contentType = "image/jpeg";
        else if (isWebp(bytes)) contentType = "image/webp";
        else throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Choose a PNG, JPG, JPEG, or WebP image.");

        boolean extensionMatches = switch (extension) {
            case "png" -> contentType.equals("image/png");
            case "jpg", "jpeg" -> contentType.equals("image/jpeg");
            case "webp" -> contentType.equals("image/webp");
            default -> false;
        };
        if (!extensionMatches) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "The file extension does not match the image format.");
        }

        if (!contentType.equals("image/webp")) {
            BufferedImage image = ImageIO.read(new ByteArrayInputStream(bytes));
            if (image == null) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "The image file is damaged.");
            }
            validateDimensions(image.getWidth(), image.getHeight());
        } else {
            int[] dimensions = webpDimensions(bytes);
            if (dimensions == null) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "The WebP image is damaged.");
            }
            validateDimensions(dimensions[0], dimensions[1]);
        }
        return contentType;
    }

    private static void validateDimensions(int width, int height) {
        if (width < 32 || height < 32 || width > MAX_AVATAR_DIMENSION
                || height > MAX_AVATAR_DIMENSION
                || (long) width * height > MAX_AVATAR_PIXELS) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Image dimensions must be between 32 and 4096 pixels per side.");
        }
    }

    private static boolean isPng(byte[] bytes) {
        byte[] signature = {(byte) 0x89, 'P', 'N', 'G', 13, 10, 26, 10};
        for (int i = 0; i < signature.length; i++) if (bytes[i] != signature[i]) return false;
        return true;
    }

    private static boolean isJpeg(byte[] bytes) {
        return (bytes[0] & 0xff) == 0xff && (bytes[1] & 0xff) == 0xd8
                && (bytes[2] & 0xff) == 0xff;
    }

    private static boolean isWebp(byte[] bytes) {
        return bytes.length >= 30 && ascii(bytes, 0, "RIFF") && ascii(bytes, 8, "WEBP");
    }

    private static int[] webpDimensions(byte[] bytes) {
        String chunk = new String(bytes, 12, 4, java.nio.charset.StandardCharsets.US_ASCII);
        if (chunk.equals("VP8X")) {
            int width = 1 + unsigned24LittleEndian(bytes, 24);
            int height = 1 + unsigned24LittleEndian(bytes, 27);
            return new int[]{width, height};
        }
        if (chunk.equals("VP8L") && (bytes[20] & 0xff) == 0x2f) {
            int b1 = bytes[21] & 0xff, b2 = bytes[22] & 0xff;
            int b3 = bytes[23] & 0xff, b4 = bytes[24] & 0xff;
            return new int[]{1 + b1 + ((b2 & 0x3f) << 8),
                    1 + ((b2 >> 6) | (b3 << 2) | ((b4 & 0x0f) << 10))};
        }
        if (chunk.equals("VP8 ") && (bytes[23] & 0xff) == 0x9d
                && (bytes[24] & 0xff) == 0x01 && (bytes[25] & 0xff) == 0x2a) {
            int width = ((bytes[26] & 0xff) | ((bytes[27] & 0xff) << 8)) & 0x3fff;
            int height = ((bytes[28] & 0xff) | ((bytes[29] & 0xff) << 8)) & 0x3fff;
            return new int[]{width, height};
        }
        return null;
    }

    private static int unsigned24LittleEndian(byte[] bytes, int offset) {
        return (bytes[offset] & 0xff) | ((bytes[offset + 1] & 0xff) << 8)
                | ((bytes[offset + 2] & 0xff) << 16);
    }

    private static boolean ascii(byte[] bytes, int offset, String value) {
        for (int i = 0; i < value.length(); i++) if (bytes[offset + i] != value.charAt(i)) return false;
        return true;
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

        log.info("👤 [Profile] Fetched profile for player ID: {} | Name: {} | Coins: {}",
                userId, profile.getDisplayName(), wallet.getBalance());

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

        log.info("🔍 [Profile Search] Found player by username: {} -> ID: {}", username, profile.getUserId());

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
        setString(payload, "authProvider", profile::setAuthProvider);
        setString(payload, "providerId", profile::setProviderId);

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

        log.info("💾 [Profile Saved] Player ID: {} | Name: {} | Coins: {} | Preferred Mode: {}",
                userId, profile.getDisplayName(), wallet.getBalance(), profile.getPreferredGameType());

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
            log.info("🎮 [Game Complete] Player ID: {} | Recorded Mode: {} | New Most Played: {}",
                    userId, gameType, profile.getMostPlayedGameType());
        } catch (Exception e) {
            log.warn("⚠️ [Game Complete] Failed to parse game type: {}", gameTypeStr);
        }

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
