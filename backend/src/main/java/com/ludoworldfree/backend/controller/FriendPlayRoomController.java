package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.service.FriendPlayRoomService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/friend-rooms")
public class FriendPlayRoomController {
    private final FriendPlayRoomService rooms;

    public FriendPlayRoomController(FriendPlayRoomService rooms) {
        this.rooms = rooms;
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> create(
            @RequestHeader("X-Player-ID") String playerId,
            @RequestBody FriendPlayRoomService.CreateRequest request) {
        return ResponseEntity.ok(rooms.create(resolve(playerId), request));
    }

    @PostMapping("/{code}/join")
    public ResponseEntity<Map<String, Object>> join(
            @PathVariable String code,
            @RequestHeader("X-Player-ID") String playerId,
            @RequestBody FriendPlayRoomService.JoinRequest request) {
        return ResponseEntity.ok(rooms.join(code, resolve(playerId), request));
    }

    @GetMapping("/{code}/preview")
    public ResponseEntity<Map<String, Object>> preview(@PathVariable String code) {
        return ResponseEntity.ok(rooms.preview(code));
    }

    @GetMapping("/{code}/status")
    public ResponseEntity<Map<String, Object>> status(
            @PathVariable String code,
            @RequestHeader("X-Player-ID") String playerId) {
        return ResponseEntity.ok(rooms.status(code, resolve(playerId)));
    }

    @PostMapping("/{code}/start")
    public ResponseEntity<Map<String, Object>> start(
            @PathVariable String code,
            @RequestHeader("X-Player-ID") String playerId) {
        return ResponseEntity.ok(rooms.start(code, resolve(playerId)));
    }

    @DeleteMapping("/{code}")
    public ResponseEntity<?> close(
            @PathVariable String code,
            @RequestHeader("X-Player-ID") String playerId) {
        rooms.close(code, resolve(playerId));
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/{code}/leave")
    public ResponseEntity<Void> leave(
            @PathVariable String code,
            @RequestHeader("X-Player-ID") String playerId) {
        rooms.leave(code, resolve(playerId));
        return ResponseEntity.noContent().build();
    }

    private UUID resolve(String playerId) {
        return PlayerIdResolver.resolve(playerId);
    }
}
