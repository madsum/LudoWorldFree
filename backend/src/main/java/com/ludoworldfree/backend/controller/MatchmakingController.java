package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.dto.MatchmakingRequestDto;
import com.ludoworldfree.backend.dto.MatchmakingResponseDto;
import com.ludoworldfree.backend.service.MatchmakingService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/matchmaking")
public class MatchmakingController {

    private final MatchmakingService matchmakingService;

    public MatchmakingController(MatchmakingService matchmakingService) {
        this.matchmakingService = matchmakingService;
    }

    @PostMapping("/join")
    public ResponseEntity<MatchmakingResponseDto> joinQueue(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestBody MatchmakingRequestDto requestDto) {
        UUID playerId = requirePlayerId(headerPlayerId);
        requestDto.setPlayerId(playerId);

        MatchmakingResponseDto response = matchmakingService.joinQueue(requestDto);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/status")
    public ResponseEntity<MatchmakingResponseDto> checkStatus(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestParam int playerCount,
            @RequestParam String sessionId) {
        UUID playerId = requirePlayerId(headerPlayerId);
        MatchmakingResponseDto response = matchmakingService.checkStatus(
                playerId, playerCount, sessionId);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/cancel")
    public ResponseEntity<?> cancelQueue(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId,
            @RequestParam(required = false) String sessionId) {
        UUID playerId = requirePlayerId(headerPlayerId);
        matchmakingService.cancelQueue(playerId, sessionId);
        return ResponseEntity.ok(Map.of("success", true, "message", "Matchmaking cancelled."));
    }

    private UUID requirePlayerId(String headerPlayerId) {
        if (headerPlayerId == null || headerPlayerId.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "A stable X-Player-ID is required for matchmaking.");
        }
        return PlayerIdResolver.resolve(headerPlayerId);
    }
}
