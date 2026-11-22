package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.OnlineMatchChatEvent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Collection;

public interface OnlineMatchChatEventRepository
        extends JpaRepository<OnlineMatchChatEvent, Long> {
    List<OnlineMatchChatEvent> findByRoomIdAndIdGreaterThanOrderByIdAsc(
            String roomId, long id);

    List<OnlineMatchChatEvent> findByRoomIdInAndIdGreaterThanOrderByIdAsc(
            Collection<String> roomIds, long id);
}
