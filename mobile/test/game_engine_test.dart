import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/game/domain/models/board_position.dart';
import 'package:mobile/features/game/domain/game_engine.dart';
import 'package:mobile/features/game/domain/models/ludo_color.dart';
import 'package:mobile/features/game/domain/models/pawn_model.dart';
import 'package:mobile/features/game/domain/models/player_model.dart';

void main() {
  group('Ludo GameEngine Tests', () {
    test('Each color has five home squares before the finish', () {
      for (final color in LudoColor.values) {
        expect(BoardPosition.getHomeStretch(color), hasLength(5));
        final finish = BoardPosition.getPositionForStep(color, 0, 56);
        expect(finish.x, 7);
        expect(finish.y, 7);
      }
    });

    test('Captured pawns return directly to their own yard', () {
      for (final color in LudoColor.values) {
        final path = BoardPosition.calculatePathSequence(
          color: color,
          pawnId: 0,
          fromStep: 24,
          toStep: -1,
        );
        final yard = BoardPosition.getYardPositions(color).first;

        expect(path, hasLength(2));
        expect(path.last.x, yard.x);
        expect(path.last.y, yard.y);
      }
    });

    test('Yard pawn requires rolling a 6 to move', () {
      final player = PlayerModel.initial(
        id: 'player_1',
        name: 'Red Player',
        color: LudoColor.red,
        isBot: false,
      );

      final movableOn5 = GameEngine.getMovablePawns(player, 5);
      expect(movableOn5.isEmpty, isTrue);

      final movableOn6 = GameEngine.getMovablePawns(player, 6);
      expect(movableOn6.length, equals(4));
    });

    test('On board pawn moves with any roll that does not overshoot home', () {
      final pawn = const PawnModel(id: 0, color: LudoColor.red, stepCount: 10);
      final player = PlayerModel(
        id: 'player_1',
        name: 'Red Player',
        color: LudoColor.red,
        isBot: false,
        pawns: [pawn],
      );

      final movableOn3 = GameEngine.getMovablePawns(player, 3);
      expect(movableOn3.length, equals(1));
    });

    test('Five home stretch squares require the exact roll to finish', () {
      for (var step = 51; step <= 55; step++) {
        for (var diceValue = 1; diceValue <= 6; diceValue++) {
          final pawn = PawnModel(
            id: 0,
            color: LudoColor.blue,
            stepCount: step,
          );

          expect(
            GameEngine.isPawnMoveValid(pawn, diceValue),
            equals(step + diceValue <= 56),
            reason: 'Step $step with roll $diceValue',
          );
        }
      }

      final pawnOneStepFromFinish = const PawnModel(
        id: 0,
        color: LudoColor.blue,
        stepCount: 55,
      );
      final player = PlayerModel(
        id: 'blue',
        name: 'Blue Player',
        color: LudoColor.blue,
        isBot: false,
        pawns: [pawnOneStepFromFinish],
      );

      expect(GameEngine.getMovablePawns(player, 1), [pawnOneStepFromFinish]);
      expect(GameEngine.getMovablePawns(player, 2), isEmpty);

      final bot = PlayerModel(
        id: 'blue_bot',
        name: 'Blue Bot',
        color: LudoColor.blue,
        isBot: true,
        pawns: [pawnOneStepFromFinish],
      );
      expect(
        GameEngine.selectBestBotMove(
          players: [bot],
          botPlayer: bot,
          movablePawns: [pawnOneStepFromFinish],
          diceValue: 2,
        ),
        isNull,
      );
    });

    test('Captures opponent pawn on non-safe tile', () {
      // Red entry 1 + step 14 = Global 15. Green entry 14 + step 1 = Global 15.
      final redPawn = const PawnModel(id: 0, color: LudoColor.red, stepCount: 14);
      final greenPawn = const PawnModel(id: 0, color: LudoColor.green, stepCount: 1); // Global tile 15

      final redPlayer = PlayerModel(
        id: 'red',
        name: 'Red Player',
        color: LudoColor.red,
        isBot: false,
        pawns: [redPawn],
      );

      final greenPlayer = PlayerModel(
        id: 'green',
        name: 'Green Player',
        color: LudoColor.green,
        isBot: false,
        pawns: [greenPawn],
      );

      final capturable = GameEngine.findCapturableOpponentPawn(
        players: [redPlayer, greenPlayer],
        currentPlayerColor: LudoColor.red,
        targetStep: 14, // Red step 14 = Global tile 15
      );

      expect(capturable, isNotNull);
      expect(capturable?.color, equals(LudoColor.green));
    });

    test('Safe / Star tiles prevent capturing', () {
      // Global Tile 0 is Red Star Tile (Safe)
      // Green entry 14 + step 38 = Global 0
      final greenPawnOnRedStart = const PawnModel(id: 0, color: LudoColor.green, stepCount: 38);

      final redPlayer = PlayerModel.initial(
        id: 'red',
        name: 'Red Player',
        color: LudoColor.red,
        isBot: false,
      );

      final greenPlayer = PlayerModel(
        id: 'green',
        name: 'Green Player',
        color: LudoColor.green,
        isBot: false,
        pawns: [greenPawnOnRedStart],
      );

      final capturable = GameEngine.findCapturableOpponentPawn(
        players: [redPlayer, greenPlayer],
        currentPlayerColor: LudoColor.red,
        targetStep: 50, // Red entry 1 + step 50 = Global Tile 0 (Red Star Tile)
      );

      expect(capturable, isNull);
    });

    test('Smart AI Bot prioritizes capturing opponent', () {
      final pawn1 = const PawnModel(id: 0, color: LudoColor.red, stepCount: 5);
      final pawn2 = const PawnModel(id: 1, color: LudoColor.red, stepCount: 9); // Move 5 steps to step 14 (Global 15)

      final greenPawn = const PawnModel(id: 0, color: LudoColor.green, stepCount: 1); // Global 15

      final redBot = PlayerModel(
        id: 'red_bot',
        name: 'Red Bot',
        color: LudoColor.red,
        isBot: true,
        pawns: [pawn1, pawn2],
      );

      final greenPlayer = PlayerModel(
        id: 'green',
        name: 'Green Player',
        color: LudoColor.green,
        isBot: false,
        pawns: [greenPawn],
      );

      final bestPawn = GameEngine.selectBestBotMove(
        players: [redBot, greenPlayer],
        botPlayer: redBot,
        movablePawns: [pawn1, pawn2],
        diceValue: 5,
      );

      expect(bestPawn?.id, equals(1)); // Bot chooses pawn2 to perform capture!
    });
  });
}
