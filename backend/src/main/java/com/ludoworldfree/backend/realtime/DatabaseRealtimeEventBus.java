package com.ludoworldfree.backend.realtime;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import jakarta.annotation.PreDestroy;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;
import javax.sql.DataSource;
import org.postgresql.PGConnection;
import org.postgresql.PGNotification;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Cross-instance, ephemeral event fanout using the existing PostgreSQL service.
 * Each Cloud Run instance owns one LISTEN connection; notifications wake each
 * instance and the payload is read from the durable table after transaction commit.
 */
@Component
public class DatabaseRealtimeEventBus {
    private static final Logger log = LoggerFactory.getLogger(DatabaseRealtimeEventBus.class);
    private static final String CHANNEL = "ludoworld_realtime_v1";

    private final JdbcTemplate jdbc;
    private final DataSource dataSource;
    private final ObjectMapper objectMapper;
    private final String instanceId = System.getenv().getOrDefault("K_REVISION", "local")
            + ":" + java.util.UUID.randomUUID();
    private final CopyOnWriteArrayList<Consumer<JsonNode>> listeners =
            new CopyOnWriteArrayList<>();
    private final AtomicBoolean running = new AtomicBoolean(true);
    private final Thread listenerThread;

    public DatabaseRealtimeEventBus(JdbcTemplate jdbc, DataSource dataSource,
                                    ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.dataSource = dataSource;
        this.objectMapper = objectMapper;
        this.listenerThread = new Thread(this::listenForever, "realtime-db-listener");
        this.listenerThread.setDaemon(true);
        this.listenerThread.start();
    }

    public void addListener(Consumer<JsonNode> listener) {
        listeners.add(listener);
    }

    /** Stores the event and publishes its ID inside the caller's DB transaction. */
    public void publish(Object payload) {
        try {
            ObjectNode event = objectMapper.valueToTree(payload);
            event.put("sourceInstanceId", instanceId);
            String json = objectMapper.writeValueAsString(event);
            Long eventId = jdbc.queryForObject(
                    "INSERT INTO realtime_events (payload) VALUES (?::jsonb) RETURNING id",
                    Long.class, json);
            if (eventId == null) throw new IllegalStateException("Realtime event was not stored.");
            jdbc.execute((ConnectionCallback<Void>) connection -> {
                try (PreparedStatement statement = connection.prepareStatement(
                        "SELECT pg_notify(?, ?)")) {
                    statement.setString(1, CHANNEL);
                    statement.setString(2, eventId.toString());
                    statement.execute();
                }
                return null;
            });
        } catch (Exception exception) {
            throw new IllegalStateException("Realtime event could not be published.", exception);
        }
    }

    public String instanceId() {
        return instanceId;
    }

    private void listenForever() {
        while (running.get()) {
            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                connection.setAutoCommit(true);
                statement.execute("LISTEN " + CHANNEL);
                PGConnection pg = connection.unwrap(PGConnection.class);
                log.info("PostgreSQL realtime listener connected.");
                while (running.get() && !connection.isClosed()) {
                    PGNotification[] notifications = pg.getNotifications(1000);
                    if (notifications == null) continue;
                    for (PGNotification notification : notifications) {
                        dispatch(notification.getParameter());
                    }
                }
            } catch (Exception exception) {
                if (running.get()) {
                    log.warn("PostgreSQL realtime listener disconnected; retrying: {}",
                            exception.getMessage());
                    try {
                        Thread.sleep(1000);
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                        return;
                    }
                }
            }
        }
    }

    private void dispatch(String eventId) {
        try {
            String json = jdbc.queryForObject(
                    "SELECT payload::text FROM realtime_events WHERE id = ?",
                    String.class, Long.parseLong(eventId));
            JsonNode event = objectMapper.readTree(json);
            for (Consumer<JsonNode> listener : listeners) {
                try {
                    listener.accept(event);
                } catch (RuntimeException exception) {
                    log.error("Realtime event handler failed: {}", exception.getMessage(), exception);
                }
            }
        } catch (Exception exception) {
            log.warn("Could not dispatch realtime event {}: {}", eventId, exception.getMessage());
        }
    }

    @Scheduled(fixedDelayString = "${realtime.events.cleanup-millis:60000}")
    public void deleteExpiredEvents() {
        jdbc.update("DELETE FROM realtime_events WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '5 minutes'");
    }

    @PreDestroy
    public void stop() {
        running.set(false);
        listenerThread.interrupt();
        try {
            listenerThread.join(1500);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
        }
    }
}
