import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/game/domain/models/ludo_color.dart';
import 'package:mobile/features/game/domain/models/player_model.dart';
import 'package:mobile/features/game/presentation/controllers/game_controller.dart';

List<PlayerModel> _players() => [
      PlayerModel.initial(
        id: 'red',
        name: 'Red Player',
        color: LudoColor.red,
        isBot: false,
      ),
      PlayerModel.initial(
        id: 'yellow',
        name: 'Yellow Player',
        color: LudoColor.yellow,
        isBot: false,
      ),
    ];

void main() {
  test('rapid manual dice taps roll once without a missed-turn strike',
      () async {
    final notifier = GameNotifier();
    addTearDown(notifier.dispose);
    notifier.startNewGame(players: _players());

    await Future.wait([
      notifier.rollDice(),
      notifier.rollDice(),
    ]);

    expect(notifier.state.players.first.missedTurns, 0);
    expect(notifier.state.playerDiceValues['red'], isNotNull);
  });

  test('five-second timeout records one strike and automatically rolls',
      () async {
    final notifier = GameNotifier();
    addTearDown(notifier.dispose);
    notifier.startNewGame(players: _players());

    await Future<void>.delayed(
      GameNotifier.turnDuration + const Duration(milliseconds: 800),
    );

    expect(notifier.state.players.first.missedTurns, 1);
    expect(notifier.state.players.last.missedTurns, 0);
    expect(notifier.state.playerDiceValues['red'], isNotNull);
  });

  test('pausing and resuming preserves the remaining turn time', () async {
    final notifier = GameNotifier();
    addTearDown(notifier.dispose);
    notifier.startNewGame(players: _players());

    await Future<void>.delayed(const Duration(milliseconds: 500));
    notifier.pauseTurnTimer();
    final remaining = notifier.state.turnTimerRemainingMilliseconds;
    expect(remaining, greaterThan(0));
    expect(remaining, lessThan(GameNotifier.turnDuration.inMilliseconds));

    await Future<void>.delayed(
      GameNotifier.turnDuration + const Duration(milliseconds: 100),
    );
    expect(notifier.state.players.first.missedTurns, 0);

    notifier.resumeTurnTimer();
    await Future<void>.delayed(Duration(milliseconds: remaining + 800));
    expect(notifier.state.players.first.missedTurns, 1);
  });
}
