package com.ludoworldfree.backend.realtime;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.google.api.core.ApiFuture;
import com.google.api.core.ApiFutureCallback;
import com.google.api.core.ApiFutures;
import com.google.common.util.concurrent.MoreExecutors;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.cloud.pubsub.v1.MessageReceiver;
import com.google.cloud.pubsub.v1.Subscriber;
import com.google.cloud.pubsub.v1.SubscriptionAdminClient;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.ExpirationPolicy;
import com.google.pubsub.v1.ProjectSubscriptionName;
import com.google.pubsub.v1.ProjectTopicName;
import com.google.pubsub.v1.PubsubMessage;
import com.google.pubsub.v1.Subscription;
import jakarta.annotation.PreDestroy;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/** Fanout bus: each live Cloud Run instance owns a Pub/Sub subscription to the topic. */
@Component
public class PubSubRealtimeEventBus {
    private static final Logger log = LoggerFactory.getLogger(PubSubRealtimeEventBus.class);
    private final ObjectMapper objectMapper;
    private final String projectId;
    private final String topicId;
    private final Environment environment;
    private final String instanceId = System.getenv().getOrDefault("K_REVISION", "local")
            + ":" + java.util.UUID.randomUUID();
    private final CopyOnWriteArrayList<Consumer<JsonNode>> listeners =
            new CopyOnWriteArrayList<>();
    private final AtomicBoolean started = new AtomicBoolean();
    private volatile Publisher publisher;
    private volatile Subscriber subscriber;
    private volatile ProjectSubscriptionName subscriptionName;
    private volatile SubscriptionAdminClient subscriptionAdmin;

    public PubSubRealtimeEventBus(ObjectMapper objectMapper,
                                  Environment environment,
                                  @Value("${realtime.pubsub.project:${GOOGLE_CLOUD_PROJECT:}}") String projectId,
                                  @Value("${realtime.pubsub.topic:${REALTIME_PUBSUB_TOPIC:}}") String topicId) {
        this.objectMapper = objectMapper;
        this.environment = environment;
        this.projectId = projectId;
        this.topicId = topicId;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void start() {
        if (!started.compareAndSet(false, true) || topicId.isBlank()) {
            if (topicId.isBlank() && environment.matchesProfiles("prod")) {
                throw new IllegalStateException("REALTIME_PUBSUB_TOPIC is required in production; "
                        + "refusing to start with instance-local realtime routing.");
            }
            if (topicId.isBlank()) log.warn("Realtime Pub/Sub is disabled; events stay within one instance.");
            return;
        }
        try {
            ProjectTopicName topic = ProjectTopicName.of(projectId, topicId);
            publisher = Publisher.newBuilder(topic).build();
            subscriptionAdmin = SubscriptionAdminClient.create();
            String subscriptionId = "ludo-" + java.util.UUID.randomUUID().toString().replace("-", "");
            subscriptionName = ProjectSubscriptionName.of(projectId, subscriptionId);
            Subscription subscription = Subscription.newBuilder()
                    .setName(subscriptionName.toString())
                    .setTopic(topic.toString())
                    .setAckDeadlineSeconds(20)
                    .setMessageRetentionDuration(com.google.protobuf.Duration.newBuilder()
                            .setSeconds(3600).build())
                    .setExpirationPolicy(ExpirationPolicy.newBuilder()
                            .setTtl(com.google.protobuf.Duration.newBuilder()
                                    .setSeconds(86_400).build())
                            .build())
                    .build();
            subscriptionAdmin.createSubscription(subscription);
            MessageReceiver receiver = (message, consumer) -> {
                try {
                    dispatch(message.getData().toStringUtf8(), true);
                    consumer.ack();
                } catch (RuntimeException exception) {
                    log.error("Realtime event dispatch failed; message will be retried: {}",
                            exception.getMessage(), exception);
                    consumer.nack();
                }
            };
            subscriber = Subscriber.newBuilder(subscriptionName, receiver).build();
            subscriber.startAsync().awaitRunning();
            log.info("Realtime Pub/Sub fanout is active on {}.", topic);
        } catch (Exception exception) {
            closeClients();
            throw new IllegalStateException("Realtime Pub/Sub could not start; refusing local-only mode.",
                    exception);
        }
    }

    public void addListener(Consumer<JsonNode> listener) {
        listeners.add(listener);
    }

    public String instanceId() {
        return instanceId;
    }

    public ApiFuture<String> publish(Object payload) {
        try {
            ObjectNode event = objectMapper.valueToTree(payload);
            event.put("sourceInstanceId", instanceId);
            String json = objectMapper.writeValueAsString(event);
            Publisher activePublisher = publisher;
            if (activePublisher == null) {
                dispatch(json, false);
                return ApiFutures.immediateFuture("local");
            }
            ApiFuture<String> published = activePublisher.publish(PubsubMessage.newBuilder()
                    .setData(ByteString.copyFromUtf8(json))
                    .build());
            ApiFutures.addCallback(published, new ApiFutureCallback<>() {
                @Override
                public void onFailure(Throwable failure) {
                    log.error("Realtime event publish failed: {}", failure.getMessage(), failure);
                }

                @Override
                public void onSuccess(String messageId) {
                    log.debug("Published realtime event {}", messageId);
                }
            }, MoreExecutors.directExecutor());
            return published;
        } catch (Exception exception) {
            throw new IllegalStateException("Realtime event could not be published.", exception);
        }
    }

    private void dispatch(String json, boolean ignoreOwnMessages) {
        try {
            JsonNode event = objectMapper.readTree(json);
            if (ignoreOwnMessages && instanceId.equals(event.path("sourceInstanceId").asText())) return;
            for (Consumer<JsonNode> listener : listeners) listener.accept(event);
        } catch (Exception exception) {
            throw new IllegalArgumentException("Realtime event payload is invalid.", exception);
        }
    }

    @PreDestroy
    public void close() {
        closeClients();
    }

    private void closeClients() {
        Subscriber activeSubscriber = subscriber;
        if (activeSubscriber != null) {
            activeSubscriber.stopAsync();
            try { activeSubscriber.awaitTerminated(2, TimeUnit.SECONDS); }
            catch (Exception ignored) {}
        }
        Publisher activePublisher = publisher;
        if (activePublisher != null) {
            try { activePublisher.shutdown(); }
            catch (Exception ignored) {}
        }
        SubscriptionAdminClient admin = subscriptionAdmin;
        ProjectSubscriptionName name = subscriptionName;
        if (admin != null && name != null) {
            try { admin.deleteSubscription(name); }
            catch (Exception exception) {
                log.debug("Temporary Pub/Sub subscription cleanup deferred: {}", exception.getMessage());
            }
            admin.close();
        }
    }
}
