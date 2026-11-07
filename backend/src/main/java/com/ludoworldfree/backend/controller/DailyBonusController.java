package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.service.DailyBonusService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/rewards/daily-bonus")
public class DailyBonusController {
    private final DailyBonusService dailyBonusService;

    public DailyBonusController(DailyBonusService dailyBonusService) {
        this.dailyBonusService = dailyBonusService;
    }

    @GetMapping
    public ResponseEntity<?> status(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        return ResponseEntity.ok(dailyBonusService.status(PlayerIdResolver.resolve(headerPlayerId)));
    }

    @PostMapping("/claim")
    public ResponseEntity<?> claim(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        return ResponseEntity.ok(dailyBonusService.claim(PlayerIdResolver.resolve(headerPlayerId)));
    }
}
