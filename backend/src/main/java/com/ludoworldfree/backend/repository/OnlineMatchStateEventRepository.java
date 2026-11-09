package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.OnlineMatchStateEvent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface OnlineMatchStateEventRepository extends JpaRepository<OnlineMatchStateEvent, UUID> {
    List<OnlineMatchStateEvent> findByRoomIdAndRevisionGreaterThanOrderByRevisionAsc(
            String roomId, long revision);
}
