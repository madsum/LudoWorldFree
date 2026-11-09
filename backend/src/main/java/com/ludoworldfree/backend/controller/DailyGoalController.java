package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.service.DailyGoalService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/daily-goals")
public class DailyGoalController {
    private final DailyGoalService dailyGoalService;

    public DailyGoalController(DailyGoalService dailyGoalService) {
        this.dailyGoalService = dailyGoalService;
    }

    @GetMapping
    public Map<String, Object> getGoals(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        return dailyGoalService.getGoals(PlayerIdResolver.resolve(headerPlayerId));
    }

    @PostMapping("/events")
    public Map<String, Object> recordEvent(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestBody Map<String, Object> body) {
        return dailyGoalService.recordEvent(
                PlayerIdResolver.resolve(headerPlayerId),
                stringValue(body.get("eventId")),
                stringValue(body.get("eventType")),
                stringValue(body.get("gameId")));
    }

    @PostMapping("/{goalType}/claim")
    public Map<String, Object> claim(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @PathVariable String goalType) {
        return dailyGoalService.claim(PlayerIdResolver.resolve(headerPlayerId), goalType);
    }

    private static String stringValue(Object value) {
        return value == null ? null : value.toString();
    }
}
