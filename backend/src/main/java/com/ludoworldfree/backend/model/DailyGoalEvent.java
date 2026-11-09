package com.ludoworldfree.backend.model;

import jakarta.persistence.*;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "daily_goal_events", uniqueConstraints =
        @UniqueConstraint(name = "uk_daily_goal_event_player_event",
                columnNames = {"player_id", "event_id"}))
public class DailyGoalEvent {
    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;

    @Column(name = "player_id", nullable = false)
    private UUID playerId;

    @Column(name = "event_id", nullable = false, length = 160)
    private String eventId;

    @Column(name = "event_type", nullable = false, length = 40)
    private String eventType;

    @Column(name = "game_id", nullable = false, length = 100)
    private String gameId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected DailyGoalEvent() {}

    public DailyGoalEvent(UUID playerId, String eventId, String eventType, String gameId) {
        this.playerId = playerId;
        this.eventId = eventId;
        this.eventType = eventType;
        this.gameId = gameId;
    }
}
