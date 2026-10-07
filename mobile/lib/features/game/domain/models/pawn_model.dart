import 'ludo_color.dart';

const Object _undefined = Object();

class PawnModel {
  final int id; // 0..3 per player
  final LudoColor color;
  final int stepCount; // -1: Yard, 0..50: Main Path, 51..55: Home Stretch, 56: Finished in Home
  final String? pairId;
  final bool isPairSelected;

  const PawnModel({
    required this.id,
    required this.color,
    this.stepCount = -1,
    this.pairId,
    this.isPairSelected = false,
  });

  bool get isYard => stepCount == -1;
  bool get isFinished => stepCount == 56;
  bool get isInHomeStretch => stepCount >= 51 && stepCount <= 55;
  bool get isOnBoard => stepCount >= 0 && stepCount <= 55;
  bool get isPaired => pairId != null;

  /// Returns the global 0..51 main track tile index if on the main track
  int? get globalTileIndex {
    if (stepCount < 0 || stepCount > 50) return null;
    return (color.actualEntryTrackIndex + stepCount) % 52;
  }

  PawnModel copyWith({
    int? stepCount,
    Object? pairId = _undefined,
    bool? isPairSelected,
  }) {
    return PawnModel(
      id: id,
      color: color,
      stepCount: stepCount ?? this.stepCount,
      pairId: pairId == _undefined ? this.pairId : (pairId as String?),
      isPairSelected: isPairSelected ?? this.isPairSelected,
    );
  }
}
