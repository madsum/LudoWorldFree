import 'ludo_color.dart';

class PawnModel {
  final int id; // 0..3 per player
  final LudoColor color;
  final int stepCount; // -1: Yard, 0..50: Main Path, 51..56: Home Stretch, 57: Finished in Home

  const PawnModel({
    required this.id,
    required this.color,
    this.stepCount = -1,
  });

  bool get isYard => stepCount == -1;
  bool get isFinished => stepCount == 57;
  bool get isInHomeStretch => stepCount >= 51 && stepCount <= 56;
  bool get isOnBoard => stepCount >= 0 && stepCount <= 56;

  /// Returns the global 0..51 main track tile index if on the main track
  int? get globalTileIndex {
    if (stepCount < 0 || stepCount > 50) return null;
    return (color.startTileIndex + stepCount) % 52;
  }

  PawnModel copyWith({
    int? stepCount,
  }) {
    return PawnModel(
      id: id,
      color: color,
      stepCount: stepCount ?? this.stepCount,
    );
  }
}
