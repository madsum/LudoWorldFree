import 'ludo_color.dart';

class BoardPosition {
  final int x; // 0..14
  final int y; // 0..14

  const BoardPosition(this.x, this.y);

  /// 52 Main Track Tile Coordinates on a 15x15 Ludo Board Grid
  static const List<BoardPosition> mainTrack = [
    // Red Start & Track (0..5)
    BoardPosition(1, 6), BoardPosition(2, 6), BoardPosition(3, 6), BoardPosition(4, 6), BoardPosition(5, 6),
    BoardPosition(6, 5), BoardPosition(6, 4), BoardPosition(6, 3), BoardPosition(6, 2), BoardPosition(6, 1), BoardPosition(6, 0),
    BoardPosition(7, 0), // Top Turn
    BoardPosition(8, 0), // Green Start Area
    BoardPosition(8, 1), BoardPosition(8, 2), BoardPosition(8, 3), BoardPosition(8, 4), BoardPosition(8, 5),
    BoardPosition(9, 6), BoardPosition(10, 6), BoardPosition(11, 6), BoardPosition(12, 6), BoardPosition(13, 6), BoardPosition(14, 6),
    BoardPosition(14, 7), // Right Turn
    BoardPosition(14, 8), // Yellow Start Area
    BoardPosition(13, 8), BoardPosition(12, 8), BoardPosition(11, 8), BoardPosition(10, 8), BoardPosition(9, 8),
    BoardPosition(8, 9), BoardPosition(8, 10), BoardPosition(8, 11), BoardPosition(8, 12), BoardPosition(8, 13), BoardPosition(8, 14),
    BoardPosition(7, 14), // Bottom Turn
    BoardPosition(6, 14), // Blue Start Area
    BoardPosition(6, 13), BoardPosition(6, 12), BoardPosition(6, 11), BoardPosition(6, 10), BoardPosition(6, 9),
    BoardPosition(5, 8), BoardPosition(4, 8), BoardPosition(3, 8), BoardPosition(2, 8), BoardPosition(1, 8), BoardPosition(0, 8),
    BoardPosition(0, 7), // Left Turn
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
}
