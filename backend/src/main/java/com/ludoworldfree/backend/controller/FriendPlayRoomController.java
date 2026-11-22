package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.service.FriendPlayRoomService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.MediaType;
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

    @GetMapping(value = "/invite/{code}", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> inviteLandingPage(@PathVariable String code) {
        if (code == null || !code.matches("\\d{8}")) {
            return ResponseEntity.badRequest().contentType(MediaType.TEXT_HTML)
                    .body("<!doctype html><html><body>Invalid Ludo room link.</body></html>");
        }
        String html = """
                <!doctype html>
                <html lang="en">
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <title>Join a Ludo World room</title>
                  <style>
                    body{margin:0;background:#07122e;color:#fff;font:16px Arial,sans-serif;display:grid;min-height:100vh;place-items:center}
                    main{max-width:420px;padding:30px;text-align:center;background:#0d3475;border:2px solid #ffc928;border-radius:22px}
                    h1{color:#ffc928}a{display:block;margin:12px;padding:14px;background:#1766c4;color:white;border-radius:24px;text-decoration:none;font-weight:bold}
                    .code{font-size:28px;font-weight:bold;letter-spacing:3px}
                  </style>
                </head>
                <body>
                  <main>
                    <h1>Join my Ludo World game</h1>
                    <p>Room code</p><div class="code">%s</div>
                    <p id="status">Opening Ludo World…</p>
                    <a href="ludoworldfree://friend-room?code=%s">Open in Ludo World</a>
                    <a href="https://play.google.com/store/apps/details?id=nl.iprosoft.ludo">Get it on Google Play</a>
                    <a href="https://apps.apple.com/search?term=Ludo%%20World%%20Free">Find it on the App Store</a>
                  </main>
                  <script>
                    const appUrl='ludoworldfree://friend-room?code=%s';
                    const isApple=/iphone|ipad|ipod/i.test(navigator.userAgent);
                    const isAndroid=/android/i.test(navigator.userAgent);
                    const storeUrl=isApple
                      ? 'https://apps.apple.com/search?term=Ludo%%20World%%20Free'
                      : 'https://play.google.com/store/apps/details?id=nl.iprosoft.ludo';
                    if(isApple||isAndroid){
                      window.location.href=appUrl;
                      setTimeout(()=>{if(!document.hidden)window.location.href=storeUrl;},1600);
                    }else{
                      document.getElementById('status').textContent='Open this link on your phone to join, or install the app below.';
                    }
                  </script>
                </body>
                </html>
                """.formatted(code, code, code);
        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(html);
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
