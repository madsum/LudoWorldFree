import '../../../game/domain/models/ludo_color.dart';
import '../../../game/domain/models/player_model.dart';

class BuddyGameMatch {
  const BuddyGameMatch({
    required this.players,
    required this.roomId,
    required this.localPlayerId,
    required this.localColor,
  });

  final List<PlayerModel> players;
  final String roomId;
  final String localPlayerId;
  final LudoColor localColor;

  static BuddyGameMatch? parse(dynamic value) {
    if (value is! Map) return null;
    final roomId = value['roomId']?.toString();
    final localPlayerId = value['playerId']?.toString();
    final rawPlayers = value['players'];
    if (roomId == null || localPlayerId == null || rawPlayers is! List) {
      return null;
    }

    final players = <PlayerModel>[];
    for (final raw in rawPlayers) {
      if (raw is! Map) return null;
      final id = raw['id']?.toString();
      final name = raw['name']?.toString();
      final colorName = raw['color']?.toString();
      final colors = LudoColor.values.where((color) => color.name == colorName);
      if (id == null || name == null || colors.isEmpty) return null;
      players.add(PlayerModel.initial(
        id: id,
        name: name,
        avatarUrl: raw['avatarUrl']?.toString(),
        country: raw['country']?.toString() ?? 'World',
        countryFlag: raw['countryFlag']?.toString() ?? '🌐',
        coins: (raw['coins'] as num?)?.toInt() ?? 0,
        diamonds: (raw['diamonds'] as num?)?.toInt() ?? 0,
        color: colors.first,
        isBot: false,
      ));
    }
    if (players.length != 2 || players.any((player) => player.isBot)) {
      return null;
    }
    final localPlayer = players.where((player) => player.id == localPlayerId);
    if (localPlayer.isEmpty) return null;
    return BuddyGameMatch(
      players: players,
      roomId: roomId,
      localPlayerId: localPlayerId,
      localColor: localPlayer.first.color,
    );
  }
}
