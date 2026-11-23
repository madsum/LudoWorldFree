package com.ludoworldfree.backend.controller;

import com.ludoworldfree.backend.service.ReferralService;
import com.ludoworldfree.backend.util.PlayerIdResolver;
import jakarta.servlet.http.HttpServletRequest;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/referrals")
public class ReferralController {
    private final ReferralService referralService;

    public ReferralController(ReferralService referralService) {
        this.referralService = referralService;
    }

    @GetMapping("/me")
    public ResponseEntity<?> details(
            @RequestHeader(value = "X-Player-ID", required = false) String playerId,
            HttpServletRequest request) {
        Map<String, Object> response = referralService.details(PlayerIdResolver.resolve(playerId));
        String invitePath = request.getRequestURL().toString().replaceFirst("/me$", "/invite/")
                + response.get("code");
        response.put("inviteUrl", invitePath);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/claim")
    public ResponseEntity<?> claim(
            @RequestHeader(value = "X-Player-ID", required = false) String playerId,
            @RequestBody Map<String, Object> payload) {
        Object rawCode = payload.get("code");
        return ResponseEntity.ok(referralService.claim(PlayerIdResolver.resolve(playerId),
                rawCode == null ? null : rawCode.toString()));
    }

    @GetMapping(value = "/invite/{code}", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> inviteLanding(@PathVariable String code) {
        if (!code.matches("[A-Za-z0-9]{6,16}")) {
            return ResponseEntity.badRequest().body("Invalid referral link.");
        }
        String normalized = code.toUpperCase();
        String appLink = "ludoworldfree://referral?code=" + normalized;
        String playUrl = "https://play.google.com/store/apps/details?id=nl.iprosoft.ludo&referrer="
                + URLEncoder.encode("referral_code=" + normalized, StandardCharsets.UTF_8);
        String html = """
                <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
                <meta charset="utf-8"><title>Join Ludo World Free</title>
                <style>body{margin:0;background:#07122e;color:#fff;font:18px Arial,sans-serif;display:grid;min-height:100vh;place-items:center}.card{max-width:440px;margin:24px;padding:28px;border:2px solid #ffd447;border-radius:24px;text-align:center}h1{color:#ffd447}a{display:block;background:#ffd447;color:#07122e;text-decoration:none;font-weight:bold;padding:16px;margin:14px 0;border-radius:14px}.muted{color:#ccd3e4;font-size:15px}</style>
                </head><body><main class="card"><h1>Play Ludo World Free</h1>
                <p>Your friend invited you!</p><p>Install the app and get <b>1,000 gold coins</b>. Your friend gets 10,000 coins.</p>
                <a href="%s">Open Ludo World</a><a href="%s">Install on Google Play</a>
                <a href="https://apps.apple.com/search?term=Ludo%%20World%%20Free">Find it on the App Store</a>
                <p class="muted">If you install first, return here and tap “Open Ludo World” to claim your bonus.</p>
                </main><script>setTimeout(function(){window.location.href='%s'},700);</script></body></html>
                """.formatted(appLink, playUrl, appLink);
        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(html);
    }
}
