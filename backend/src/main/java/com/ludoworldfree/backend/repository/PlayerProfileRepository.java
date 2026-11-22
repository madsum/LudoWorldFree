package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.PlayerProfile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Collection;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface PlayerProfileRepository extends JpaRepository<PlayerProfile, UUID> {
    Optional<PlayerProfile> findByUserId(UUID userId);
    List<PlayerProfile> findByUserIdIn(Collection<UUID> userIds);
    boolean existsByUserId(UUID userId);
    Optional<PlayerProfile> findByDisplayName(String displayName);
    boolean existsByDisplayName(String displayName);

    @Query(value = """
            SELECT CAST(p.user_id AS VARCHAR) AS "playerId",
                   p.display_name AS "displayName",
                   p.avatar_url AS "avatarUrl",
                   p.country_flag AS "countryFlag",
                   COALESCE(w.balance, 0) AS "goldCoins",
                   (COALESCE(p.classic_play_count, 0) +
                    COALESCE(p.quick_play_count, 0) +
                    COALESCE(p.team_up_play_count, 0) +
                    COALESCE(p.computer_play_count, 0) +
                    COALESCE(p.pass_n_play_play_count, 0)) AS "gamesPlayed"
            FROM player_profiles p
            LEFT JOIN player_wallets w ON w.player_id = p.user_id
            ORDER BY "goldCoins" DESC, "gamesPlayed" DESC, p.display_name ASC
            LIMIT :limit
            """, nativeQuery = true)
    List<LeaderboardEntryProjection> findLeaderboard(@Param("limit") int limit);
}
