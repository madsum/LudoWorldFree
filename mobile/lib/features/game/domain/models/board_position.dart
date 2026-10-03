import 'ludo_color.dart';

class BoardPosition {
  final int x; // 0..14
  final int y; // 0..14

  const BoardPosition(this.x, this.y);

  /// Exactly 52 Main Track Tile Coordinates on a 15x15 Ludo Board Grid
  static const List<BoardPosition> mainTrack = [
    // Red Start & Track (0..11)
    BoardPosition(0, 6), BoardPosition(1, 6), BoardPosition(2, 6), BoardPosition(3, 6), BoardPosition(4, 6), BoardPosition(5, 6),
    BoardPosition(6, 5), BoardPosition(6, 4), BoardPosition(6, 3), BoardPosition(6, 2), BoardPosition(6, 1), BoardPosition(6, 0),
    BoardPosition(7, 0), // Top Turn (12)
    // Green Start Area (13..24)
    BoardPosition(8, 0), BoardPosition(8, 1), BoardPosition(8, 2), BoardPosition(8, 3), BoardPosition(8, 4), BoardPosition(8, 5),
    BoardPosition(9, 6), BoardPosition(10, 6), BoardPosition(11, 6), BoardPosition(12, 6), BoardPosition(13, 6), BoardPosition(14, 6),
    BoardPosition(14, 7), // Right Turn (25)
    // Yellow Start Area (26..37)
    BoardPosition(14, 8), BoardPosition(13, 8), BoardPosition(12, 8), BoardPosition(11, 8), BoardPosition(10, 8), BoardPosition(9, 8),
    BoardPosition(8, 9), BoardPosition(8, 10), BoardPosition(8, 11), BoardPosition(8, 12), BoardPosition(8, 13), BoardPosition(8, 14),
    BoardPosition(7, 14), // Bottom Turn (38)
    // Blue Start Area (39..50)
    BoardPosition(6, 14), BoardPosition(6, 13), BoardPosition(6, 12), BoardPosition(6, 11), BoardPosition(6, 10), BoardPosition(6, 9),
    BoardPosition(5, 8), BoardPosition(4, 8), BoardPosition(3, 8), BoardPosition(2, 8), BoardPosition(1, 8), BoardPosition(0, 8),
    BoardPosition(0, 7), // Left Turn (51)
  ];

  /// Home Stretches (51..56 step count)
  static List<BoardPosition> getHomeStretch(LudoColor color) {
    switch (color) {
      case LudoColor.red:
        return const [
          BoardPosition(1, 7), BoardPosition(2, 7), BoardPosition(3, 7),
          BoardPosition(4, 7), BoardPosition(5, 7), BoardPosition(6, 7),
        ];
      case LudoColor.green:
        return const [
          BoardPosition(7, 1), BoardPosition(7, 2), BoardPosition(7, 3),
          BoardPosition(7, 4), BoardPosition(7, 5), BoardPosition(7, 6),
        ];
      case LudoColor.yellow:
        return const [
          BoardPosition(13, 7), BoardPosition(12, 7), BoardPosition(11, 7),
          BoardPosition(10, 7), BoardPosition(9, 7), BoardPosition(8, 7),
        ];
      case LudoColor.blue:
        return const [
          BoardPosition(7, 13), BoardPosition(7, 12), BoardPosition(7, 11),
          BoardPosition(7, 10), BoardPosition(7, 9), BoardPosition(7, 8),
        ];
    }
  }

  /// Yard Pawn Positions (4 per color)
  static List<BoardPosition> getYardPositions(LudoColor color) {
    switch (color) {
      case LudoColor.red:
        return const [BoardPosition(2, 2), BoardPosition(3, 2), BoardPosition(2, 3), BoardPosition(3, 3)];
      case LudoColor.green:
        return const [BoardPosition(11, 2), BoardPosition(12, 2), BoardPosition(11, 3), BoardPosition(12, 3)];
      case LudoColor.yellow:
        return const [BoardPosition(11, 11), BoardPosition(12, 11), BoardPosition(11, 12), BoardPosition(12, 12)];
      case LudoColor.blue:
        return const [BoardPosition(2, 11), BoardPosition(3, 11), BoardPosition(2, 12), BoardPosition(3, 12)];
    }
  }

  /// Gets single board position for a given pawn step count
  static BoardPosition getPositionForStep(LudoColor color, int pawnId, int step) {
    if (step == -1) {
      return getYardPositions(color)[pawnId];
    } else if (step >= 0 && step <= 50) {
      final globalIdx = (color.startTileIndex + step) % 52;
      return mainTrack[globalIdx];
    } else if (step >= 51 && step <= 56) {
      return getHomeStretch(color)[step - 51];
    } else {
      // Step 57: Finished in Home Center
      return const BoardPosition(7, 7);
    }
  }

  /// Calculates step-by-step path sequence of board positions from [fromStep] to [toStep]
  static List<BoardPosition> calculatePathSequence({
    required LudoColor color,
    required int pawnId,
    required int fromStep,
    required int toStep,
  }) {
    final path = <BoardPosition>[];

    if (fromStep == -1) {
      // Leaving Yard to Start Tile (step 0)
      path.add(getYardPositions(color)[pawnId]);
      path.add(getPositionForStep(color, pawnId, 0));
    } else {
      // Moving step-by-step along main track & home stretch
      for (int step = fromStep; step <= toStep; step++) {
        path.add(getPositionForStep(color, pawnId, step));
      }
    }

    return path;
  }
}
