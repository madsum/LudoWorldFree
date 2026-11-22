package com.ludoworldfree.backend.chat;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.listener.ChannelTopic;
import org.springframework.data.redis.listener.RedisMessageListenerContainer;

@Configuration
public class ChatRedisConfiguration {
    @Bean
    RedisMessageListenerContainer chatRedisMessageListenerContainer(
            RedisConnectionFactory connectionFactory,
            ChatRedisEventListener listener) {
        RedisMessageListenerContainer container = new RedisMessageListenerContainer() {
            @Override
            public boolean isAutoStartup() {
                return false;
            }
        };
        container.setConnectionFactory(connectionFactory);
        // Do not let an unavailable Redis server prevent the game/API backend
        // from starting. ChatRedisListenerStartup retries the subscription.
        container.addMessageListener(listener,
                new ChannelTopic(ChatEventPublisher.CHANNEL));
        return container;
    }
}
