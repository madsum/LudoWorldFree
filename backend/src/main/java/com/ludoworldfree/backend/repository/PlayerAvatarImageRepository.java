package com.ludoworldfree.backend.repository;

import com.ludoworldfree.backend.model.PlayerAvatarImage;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface PlayerAvatarImageRepository extends JpaRepository<PlayerAvatarImage, UUID> {}
