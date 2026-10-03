import 'ludo_color.dart';
import 'pawn_model.dart';

class PlayerModel {
  final String id;
  final String name;
  final String? avatarUrl;
  final LudoColor color;
  final bool isBot;
  final List<PawnModel> pawns;
  final int rank; // 0: Not finished, 1: 1st Place, 2: 2nd, 3: 3rd, 4: 4th

  const PlayerModel({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.color,
    required this.isBot,
    required this.pawns,
    this.rank = 0,
  });

  bool get isWinner => rank > 0;
  bool get hasAllPawnsHome => pawns.every((p) => p.isFinished);
  int get finishedPawnsCount => pawns.where((p) => p.isFinished).length;

  factory PlayerModel.initial({
    required String id,
    required String name,
    String? avatarUrl,
    required LudoColor color,
    required bool isBot,
  }) {
    return PlayerModel(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      color: color,
      isBot: isBot,
      pawns: List.generate(
        4,
        (index) => PawnModel(id: index, color: color, stepCount: -1),
      ),
    );
  }

  PlayerModel copyWith({
    String? name,
    String? avatarUrl,
    List<PawnModel>? pawns,
    int? rank,
  }) {
    return PlayerModel(
      id: id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      color: color,
      isBot: isBot,
      pawns: pawns ?? this.pawns,
      rank: rank ?? this.rank,
    );
  }
}
