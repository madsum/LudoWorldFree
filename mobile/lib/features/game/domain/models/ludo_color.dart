import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

enum LudoColor {
  red,
  green,
  yellow,
  blue;

  Color get color {
    switch (this) {
      case LudoColor.red:
        return AppColors.red;
      case LudoColor.green:
        return AppColors.green;
      case LudoColor.yellow:
        return AppColors.gold;
      case LudoColor.blue:
        return AppColors.royalBlue;
    }
  }

  Color get lightColor {
    switch (this) {
      case LudoColor.red:
        return const Color(0xFFFF8A80);
      case LudoColor.green:
        return const Color(0xBFB9F6CA);
      case LudoColor.yellow:
        return const Color(0xFFFFE57F);
      case LudoColor.blue:
        return const Color(0xFF80D8FF);
    }
  }

  String get displayName {
    switch (this) {
      case LudoColor.red:
        return 'RED';
      case LudoColor.green:
        return 'GREEN';
      case LudoColor.yellow:
        return 'YELLOW';
      case LudoColor.blue:
        return 'BLUE';
    }
  }

  /// Global main-track index of this color's start star and pawn entry (step 0).
  int get actualEntryTrackIndex {
    switch (this) {
      case LudoColor.red:
        return 1; // BoardPosition(1, 6)
      case LudoColor.green:
        return 14; // BoardPosition(8, 1)
      case LudoColor.yellow:
        return 27; // BoardPosition(13, 8)
      case LudoColor.blue:
        return 40; // BoardPosition(6, 13)
    }
  }

  /// Alias for actualEntryTrackIndex for game engine compatibility
  int get startTileIndex => actualEntryTrackIndex;

  /// Track index immediately preceding the Home Stretch turn
  int get homeEntryIndex {
    switch (this) {
      case LudoColor.red:
        return 51; // Left Turn Tile (0, 7)
      case LudoColor.green:
        return 12; // Top Turn Tile (7, 0)
      case LudoColor.yellow:
        return 25; // Right Turn Tile (14, 7)
      case LudoColor.blue:
        return 38; // Bottom Turn Tile (7, 14)
    }
  }
}
