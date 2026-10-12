package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.dto.MatchmakingRequestDto;
import com.ludoworldfree.backend.dto.MatchmakingResponseDto;
import com.ludoworldfree.backend.service.MatchmakingService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

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
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        requestDto.setPlayerId(playerId);

        MatchmakingResponseDto response = matchmakingService.joinQueue(requestDto);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/status")
    public ResponseEntity<MatchmakingResponseDto> checkStatus(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        MatchmakingResponseDto response = matchmakingService.checkStatus(playerId);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/cancel")
    public ResponseEntity<?> cancelQueue(
            @RequestHeader(value = "X-Player-ID", required = false) String headerPlayerId) {
        UUID playerId = PlayerIdResolver.resolve(headerPlayerId);
        matchmakingService.cancelQueue(playerId);
        return ResponseEntity.ok(Map.of("success", true, "message", "Matchmaking cancelled."));
    }
}
