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

  /// Starting index on the 52-tile main track
  int get startTileIndex {
    switch (this) {
      case LudoColor.red:
        return 0;
      case LudoColor.green:
        return 13;
      case LudoColor.yellow:
        return 26;
      case LudoColor.blue:
        return 39;
    }
  }

  /// Entry tile index before turning into Home Stretch
  int get homeEntryIndex {
    switch (this) {
      case LudoColor.red:
        return 50;
      case LudoColor.green:
        return 11;
      case LudoColor.yellow:
        return 24;
      case LudoColor.blue:
        return 37;
    }
  }
}
