import 'ludo_color.dart';
import 'pawn_model.dart';

class PlayerModel {
  final String id;
  final String name;
  final String? avatarUrl;
  final String country;
  final String countryFlag;
  final int coins;
  final int diamonds;
  final LudoColor color;
  final bool isBot;
  final List<PawnModel> pawns;
  final int rank; // 0: Not finished, 1: 1st Place, 2: 2nd, 3: 3rd, 4: 4th
  final Map<LudoColor, int> killCounts;
  final int missedTurns;
  final bool isEliminated;
  final int eliminationOrder;

  const PlayerModel({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.country = 'Local Player',
    this.countryFlag = '🌐',
    this.coins = 0,
    this.diamonds = 0,
    required this.color,
    required this.isBot,
    required this.pawns,
    this.rank = 0,
    this.killCounts = const {},
    this.missedTurns = 0,
    this.isEliminated = false,
    this.eliminationOrder = 0,
  });

  bool get isWinner => rank > 0;
  bool get hasAllPawnsHome => pawns.every((p) => p.isFinished);

  factory PlayerModel.initial({
    required String id,
    required String name,
    String? avatarUrl,
    String country = 'Local Player',
    String countryFlag = '🌐',
    int coins = 0,
    int diamonds = 0,
    required LudoColor color,
    required bool isBot,
  }) {
    return PlayerModel(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      country: country,
      countryFlag: countryFlag,
      coins: coins,
      diamonds: diamonds,
      color: color,
      isBot: isBot,
      pawns: List.generate(
        4,
        (index) => PawnModel(id: index, color: color, stepCount: -1),
      ),
      killCounts: {
        for (final opponentColor in LudoColor.values) opponentColor: 0
      },
    );
  }

  PlayerModel copyWith({
    String? name,
    String? avatarUrl,
    String? country,
    String? countryFlag,
    int? coins,
    int? diamonds,
    List<PawnModel>? pawns,
    int? rank,
    Map<LudoColor, int>? killCounts,
    int? missedTurns,
    bool? isEliminated,
    int? eliminationOrder,
  }) {
    return PlayerModel(
      id: id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      country: country ?? this.country,
      countryFlag: countryFlag ?? this.countryFlag,
      coins: coins ?? this.coins,
      diamonds: diamonds ?? this.diamonds,
      color: color,
      isBot: isBot,
      pawns: pawns ?? this.pawns,
      rank: rank ?? this.rank,
      killCounts: killCounts ?? this.killCounts,
      missedTurns: missedTurns ?? this.missedTurns,
      isEliminated: isEliminated ?? this.isEliminated,
      eliminationOrder: eliminationOrder ?? this.eliminationOrder,
    );
  }
}
