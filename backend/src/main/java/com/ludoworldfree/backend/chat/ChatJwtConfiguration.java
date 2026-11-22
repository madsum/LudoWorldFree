package com.ludoworldfree.backend.chat;

import java.nio.charset.StandardCharsets;
import java.util.List;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.core.annotation.Order;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.JwtIssuerValidator;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.BadJwtException;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Configuration
public class ChatJwtConfiguration {
    private static final Logger log = LoggerFactory.getLogger(ChatJwtConfiguration.class);

    @Bean
    JwtDecoder chatJwtDecoder(
            @Value("${chat.jwt.secret:}") String secret,
            @Value("${chat.jwt.issuer:}") String issuer,
            @Value("${chat.jwt.audience:}") String audience) {
        if (secret == null || secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            log.error("Chat JWT authentication is disabled: CHAT_JWT_SECRET must be configured "
                    + "with at least 32 UTF-8 bytes. The rest of the backend will continue starting.");
            return token -> {
                // A bad token is an authentication failure (401), not an infrastructure
                // failure (500). In particular, don't let an absent chat-only secret break
                // unrelated APIs that happen to receive an Authorization header.
                throw new BadJwtException("Chat JWT authentication is not configured.");
            };
        }
        byte[] keyBytes = secret.getBytes(StandardCharsets.UTF_8);
        SecretKey key = new SecretKeySpec(keyBytes, "HmacSHA256");
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withSecretKey(key)
                .macAlgorithm(MacAlgorithm.HS256)
                .build();
        List<OAuth2TokenValidator<Jwt>> validators = new java.util.ArrayList<>();
        validators.add(new JwtTimestampValidator());
        if (issuer != null && !issuer.isBlank()) validators.add(new JwtIssuerValidator(issuer));
        if (audience != null && !audience.isBlank()) {
            validators.add(new JwtClaimValidator<List<String>>("aud",
                    audiences -> audiences != null && audiences.contains(audience)));
        }
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(validators));
        return decoder;
    }

    @Bean
    @Order(1)
    SecurityFilterChain chatSecurityFilterChain(HttpSecurity http) throws Exception {
        return http
                .securityMatcher("/api/v1/chat/**", "/ws/chat")
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize
                        .requestMatchers("/api/v1/chat/**", "/ws/chat").authenticated()
                        .anyRequest().permitAll())
                .oauth2ResourceServer(resourceServer ->
                        resourceServer.jwt(Customizer.withDefaults()))
                .build();
    }

    @Bean
    @Order(2)
    SecurityFilterChain applicationSecurityFilterChain(HttpSecurity http) throws Exception {
        // Chat JWTs are a separate authentication domain. All existing non-chat APIs
        // retain their current public-access behavior without passing through the chat
        // bearer-token decoder.
        return http
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize.anyRequest().permitAll())
                .build();
    }
}
