package com.ludoworldfree.backend.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "player_avatar_images")
public class PlayerAvatarImage {
    @Id
    @Column(name = "player_id", nullable = false)
    private UUID playerId;

    @Column(name = "content_type", nullable = false, length = 32)
    private String contentType;

    @Column(name = "image_data", nullable = false, columnDefinition = "BYTEA")
    private byte[] imageData;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    @Version
    private long version;

    protected PlayerAvatarImage() {}

    public PlayerAvatarImage(UUID playerId, String contentType, byte[] imageData) {
        this.playerId = playerId;
        this.contentType = contentType;
        this.imageData = imageData.clone();
        this.updatedAt = Instant.now();
    }

    public UUID getPlayerId() { return playerId; }
    public String getContentType() { return contentType; }
    public byte[] getImageData() { return imageData.clone(); }
    public void replace(String contentType, byte[] imageData) {
        this.contentType = contentType;
        this.imageData = imageData.clone();
        this.updatedAt = Instant.now();
    }
}
