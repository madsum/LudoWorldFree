import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/game/domain/models/ludo_color.dart';
import 'package:mobile/features/game/domain/models/player_model.dart';
import 'package:mobile/features/game/presentation/controllers/game_controller.dart';

List<PlayerModel> _players(LudoColor firstColor, LudoColor secondColor) => [
      PlayerModel.initial(
        id: 'player-a',
        name: 'Player A',
        color: firstColor,
        isBot: false,
      ),
      PlayerModel.initial(
        id: 'player-b',
        name: 'Player B',
        color: secondColor,
        isBot: false,
      ),
    ];

GameNotifier _startClient({
  required String localPlayerId,
  required LudoColor selectedColor,
  required List<PlayerModel> roomPlayers,
}) {
  final notifier = GameNotifier();
  notifier.configureOnlineMatch(
    roomId: 'room',
    playerId: localPlayerId,
    selectedColor: selectedColor,
    requestDiceRoll: (_) async => 6,
  );
  notifier.startNewGame(players: roomPlayers);
  return notifier;
}

void main() {
  group('online local-player perspective', () {
    test('both Blue selections stay Blue on their own devices', () {
      final canonicalPlayers = _players(LudoColor.blue, LudoColor.green);
      final playerA = _startClient(
        localPlayerId: 'player-a',
        selectedColor: LudoColor.blue,
        roomPlayers: canonicalPlayers,
      );
      final playerB = _startClient(
        localPlayerId: 'player-b',
        selectedColor: LudoColor.blue,
        roomPlayers: canonicalPlayers,
      );
      addTearDown(playerA.dispose);
      addTearDown(playerB.dispose);

      for (final client in [playerA, playerB]) {
        expect(
          client.currentState.players
              .singleWhere((player) => player.id == client.onlineLocalPlayerId)
              .color,
          LudoColor.blue,
        );
        expect(
          client.currentState.players
              .singleWhere((player) => player.id != client.onlineLocalPlayerId)
              .color,
          LudoColor.green,
        );
      }

      final wire = playerB.toOnlineWireJson(playerB.currentState);
      final localWirePlayer = (wire['players'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((player) => player['id'] == 'player-b');
      expect(localWirePlayer['color'], 'green');
    });

    test('Blue and Red selections render as opposite local seats', () {
      final canonicalPlayers = _players(LudoColor.red, LudoColor.yellow);
      final playerA = _startClient(
        localPlayerId: 'player-a',
        selectedColor: LudoColor.red,
        roomPlayers: canonicalPlayers,
      );
      final playerB = _startClient(
        localPlayerId: 'player-b',
        selectedColor: LudoColor.blue,
        roomPlayers: canonicalPlayers,
      );
      addTearDown(playerA.dispose);
      addTearDown(playerB.dispose);

      expect(playerA.currentState.players[0].color, LudoColor.red);
      expect(playerA.currentState.players[1].color, LudoColor.yellow);
      expect(playerB.currentState.players[1].color, LudoColor.blue);
      expect(playerB.currentState.players[0].color, LudoColor.green);

      // GameScreen rotates each selected color to board corner 3 (bottom-left).
      for (final localColor in [LudoColor.red, LudoColor.blue]) {
        final quarterTurns = (3 - localColor.index) % 4;
        expect((localColor.index + quarterTurns) % 4, 3);
        expect(((localColor.index + 2) % 4 + quarterTurns) % 4, 1);
      }
    });
  });
}
