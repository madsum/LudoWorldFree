package com.ludoworldfree.backend.chat;

import java.util.concurrent.atomic.AtomicBoolean;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.listener.RedisMessageListenerContainer;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class ChatRedisListenerStartup {
    private static final Logger log = LoggerFactory.getLogger(ChatRedisListenerStartup.class);
    private final RedisMessageListenerContainer listenerContainer;
    private final AtomicBoolean warned = new AtomicBoolean();

    public ChatRedisListenerStartup(RedisMessageListenerContainer listenerContainer) {
        this.listenerContainer = listenerContainer;
    }

    @Scheduled(fixedDelayString = "${chat.redis.listener.retry-millis:5000}",
            initialDelayString = "${chat.redis.listener.retry-millis:5000}")
    public void startOrRetry() {
        if (listenerContainer.isRunning()) return;
        try {
            listenerContainer.start();
            warned.set(false);
            log.info("Realtime chat Redis subscription is active.");
        } catch (RuntimeException exception) {
            if (warned.compareAndSet(false, true)) {
                log.warn("Redis is unavailable; matchmaking and other backend APIs remain available. "
                        + "Realtime chat will reconnect when Redis is reachable: {}",
                        exception.getMessage());
            }
        }
    }
}
