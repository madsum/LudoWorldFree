package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.OnlineMatchChatEvent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface OnlineMatchChatEventRepository
        extends JpaRepository<OnlineMatchChatEvent, Long> {
    List<OnlineMatchChatEvent> findByRoomIdAndIdGreaterThanOrderByIdAsc(
            String roomId, long id);
}
