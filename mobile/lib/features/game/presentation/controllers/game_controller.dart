import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/game_engine.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/ludo_color.dart';
import '../../domain/models/pawn_model.dart';
import '../../domain/models/player_model.dart';

final gameControllerProvider =
    StateNotifierProvider<GameNotifier, GameState>((ref) {
  return GameNotifier();
});

class GameNotifier extends StateNotifier<GameState> {
  final math.Random _random = math.Random();
  Timer? _botTimer;
  GameState? _sixSequenceSnapshot;

  GameNotifier() : super(const GameState(players: []));

  @override
  void dispose() {
    _botTimer?.cancel();
    super.dispose();
  }

  /// Initializes a new Ludo Game (Vs Computer or Pass & Play)
  void startNewGame({
    required List<PlayerModel> players,
  }) {
    _botTimer?.cancel();
    _sixSequenceSnapshot = null;
    final humanTurnIndex = players.indexWhere((player) => !player.isBot);
    final startingTurnIndex = humanTurnIndex < 0 ? 0 : humanTurnIndex;
    state = GameState(
      players: players,
      currentTurnIndex: startingTurnIndex,
      turnPhase: GameTurnPhase.rollDice,
      isDiceRolling: false,
      statusMessage: '${players[startingTurnIndex].name}\'s turn to roll!',
    );

    _checkBotTurn();
  }

  /// Rolls the 6-sided dice with 3D animation simulation
  Future<void> rollDice() async {
    if (state.turnPhase != GameTurnPhase.rollDice || state.isGameOver) return;

    state = state.copyWith(
      turnPhase: GameTurnPhase.animating,
      isDiceRolling: true,
      statusMessage: '${state.currentPlayer.name} is rolling...',
    );

    // Simulate dice rolling delay
    await Future.delayed(const Duration(milliseconds: 650));
    final diceResult = _random.nextInt(6) + 1;

    if (diceResult == 6 && state.consecutiveSixes == 0) {
      _sixSequenceSnapshot = state;
    } else if (diceResult != 6) {
      _sixSequenceSnapshot = null;
    }

    int consecutive6 = diceResult == 6 ? state.consecutiveSixes + 1 : 0;

    // Three consecutive sixes undo every move made during that six sequence.
    if (consecutive6 == 3) {
      final snapshot = _sixSequenceSnapshot;
      _sixSequenceSnapshot = null;
      final currentPlayerId = state.currentPlayer.id;
      state = GameState(
        players: snapshot?.players ?? state.players,
        currentTurnIndex: snapshot?.currentTurnIndex ?? state.currentTurnIndex,
        diceValue: diceResult,
        playerDiceValues: Map<String, int>.unmodifiable({
          ...state.playerDiceValues,
          currentPlayerId: diceResult,
        }),
        consecutiveSixes: 0,
        isDiceRolling: false,
        turnPhase: GameTurnPhase.rollDice,
        movablePawns: const [],
        lastMoveEvent: snapshot?.lastMoveEvent,
        lastCaptureEvent: snapshot?.lastCaptureEvent,
        isGameOver: snapshot?.isGameOver ?? state.isGameOver,
        winnerIds: snapshot?.winnerIds ?? state.winnerIds,
        statusMessage: 'Three 6s! Moves reverted. Roll again.',
      );
      _checkBotTurn();
      return;
    }

    final movable = GameEngine.getMovablePawns(state.currentPlayer, diceResult);

    if (movable.isEmpty) {
      state = state.copyWith(
        diceValue: diceResult,
        playerDiceValues: {
          ...state.playerDiceValues,
          state.currentPlayer.id: diceResult,
        },
        consecutiveSixes: consecutive6,
        isDiceRolling: false,
        turnPhase: GameTurnPhase.turnEnded,
        movablePawns: const [],
        statusMessage: diceResult == 6
            ? 'Rolled a 6! No valid move. Bonus roll!'
            : 'No valid moves for $diceResult.',
      );

      // Next turn delay
      await Future.delayed(const Duration(milliseconds: 900));
      if (diceResult == 6) {
        // Bonus roll if 6 rolled, otherwise next player
        state = state.copyWith(
          turnPhase: GameTurnPhase.rollDice,
          statusMessage: 'Bonus roll for 6!',
        );
        _checkBotTurn();
      } else {
        _nextTurn();
      }
    } else {
      state = state.copyWith(
        diceValue: diceResult,
        playerDiceValues: {
          ...state.playerDiceValues,
          state.currentPlayer.id: diceResult,
        },
        consecutiveSixes: consecutive6,
        isDiceRolling: false,
        movablePawns: movable,
        turnPhase: GameTurnPhase.selectPawn,
        statusMessage:
            '${state.currentPlayer.name} rolled a $diceResult! Select a token.',
      );

      // Auto-move for Bot
      if (state.isCurrentPlayerBot) {
        _scheduleBotMove();
      }
    }
  }

  /// Moves the selected pawn along the Ludo track with step-by-step animation
  Future<void> movePawn(PawnModel selectedPawn) async {
    if (state.turnPhase != GameTurnPhase.selectPawn ||
        state.diceValue == null) {
      return;
    }
    if (!state.movablePawns
        .any((p) => p.id == selectedPawn.id && p.color == selectedPawn.color)) {
      return;
    }

    final dice = state.diceValue!;
    final player = state.currentPlayer;
    // Resolve the pawn from the latest game state rather than trusting the
    // model captured by the board tap. This keeps a stale/rebuilt board from
    // advancing from an outdated square and appearing one tile too far ahead.
    final pawn = player.pawns.firstWhere(
      (candidate) => candidate.id == selectedPawn.id,
    );
    final isYardMove = pawn.isYard;

    final fromStep = pawn.stepCount;
    final newStepCount = isYardMove ? 0 : (fromStep + dice);
    // Revalidate against the latest pawn position so stale movable-pawn data
    // cannot let a pawn overshoot the exact finish step.
    if (!isYardMove && newStepCount > 57) return;

    final moveEvent = PawnMoveEvent(
      color: pawn.color,
      pawnId: pawn.id,
      fromStep: fromStep,
      toStep: newStepCount,
    );

    final updatedPawn = pawn.copyWith(stepCount: newStepCount);
    bool earnedBonusRoll = dice == 6;

    // Check for Capture / Cutting of opponent pawn
    PawnModel? capturedPawn;
    LudoColor? capturedColor;
    PawnCaptureEvent? captureEvent;

    if (!isYardMove && newStepCount <= 50) {
      capturedPawn = GameEngine.findCapturableOpponentPawn(
        players: state.players,
        currentPlayerColor: player.color,
        targetStep: newStepCount,
      );
      if (capturedPawn != null) {
        capturedColor = capturedPawn.color;
        captureEvent = PawnCaptureEvent(
          color: capturedPawn.color,
          pawnId: capturedPawn.id,
          globalTrackIndex: capturedPawn.globalTileIndex!,
        );
        earnedBonusRoll = true; // Bonus roll for capturing an opponent
      }
    }

    // Check for Reaching Home Finish (step 57)
    if (newStepCount == 57) {
      earnedBonusRoll = true; // Bonus roll for completing a pawn
    }

    // Apply pawn moves and captures to players list
    final updatedPlayers = state.players.map((p) {
      if (p.color == player.color) {
        final newPawns = p.pawns
            .map((candidate) =>
                candidate.id == pawn.id ? updatedPawn : candidate)
            .toList();
        return p.copyWith(pawns: newPawns);
      } else if (capturedColor != null && p.color == capturedColor) {
        final newPawns = p.pawns
            .map((pawn) => pawn.id == capturedPawn!.id
                ? pawn.copyWith(stepCount: -1)
                : pawn)
            .toList();
        return p.copyWith(pawns: newPawns);
      }
      return p;
    }).toList();

    // Check player completion / ranking
    final updatedCurrentPlayer =
        updatedPlayers.firstWhere((p) => p.color == player.color);
    List<String> newWinnerIds = List.from(state.winnerIds);

    if (updatedCurrentPlayer.hasAllPawnsHome &&
        !newWinnerIds.contains(updatedCurrentPlayer.id)) {
      newWinnerIds.add(updatedCurrentPlayer.id);
    }

    final isGameOver = newWinnerIds.length >= (updatedPlayers.length - 1);

    String statusMsg = capturedPawn != null
        ? '${player.name} captured a token! Extra turn.'
        : newStepCount == 57
            ? '${player.name} reached HOME! Extra turn.'
            : earnedBonusRoll
                ? '${player.name} rolled a 6! Extra turn.'
                : '${player.name} moved token.';

    // Emit animating phase and move event to presentation layer
    state = state.copyWith(
      players: updatedPlayers,
      diceValue: dice,
      turnPhase: GameTurnPhase.animating,
      movablePawns: const [],
      lastMoveEvent: moveEvent,
      lastCaptureEvent: captureEvent,
      winnerIds: newWinnerIds,
      isGameOver: isGameOver,
      statusMessage: statusMsg,
    );

    // Keep the turn animating until both the selected pawn's move and any
    // captured pawn's return to its yard have completed.
    final moveAnimationSteps = moveEvent.stepsCount;
    final captureAnimationSteps = capturedPawn == null
        ? 0
        : capturedPawn.stepCount + 1; // Back to step 0, then into the yard.
    final moveDurationMicroseconds = moveAnimationSteps * 130000;
    final captureDurationMicroseconds = captureAnimationSteps * 130000 ~/ 3;
    final animDurationMicroseconds = math
            .max(moveDurationMicroseconds, captureDurationMicroseconds)
            .toInt() +
        200000;
    await Future.delayed(
      Duration(microseconds: animDurationMicroseconds),
    );

    if (isGameOver) {
      state = state.copyWith(
        turnPhase: GameTurnPhase.turnEnded,
        statusMessage:
            'Match complete! ${updatedPlayers.firstWhere((p) => p.id == newWinnerIds.first).name} wins.',
      );
      return;
    }

    if (earnedBonusRoll) {
      state = state.copyWith(
        turnPhase: GameTurnPhase.rollDice,
      );
      _checkBotTurn();
    } else {
      _nextTurn();
    }
  }

  void _nextTurn() {
    _sixSequenceSnapshot = null;
    int nextIndex = (state.currentTurnIndex + 1) % state.players.length;

    // Skip players who have already finished all pawns
    while (state.players[nextIndex].hasAllPawnsHome) {
      nextIndex = (nextIndex + 1) % state.players.length;
    }

    state = state.copyWith(
      currentTurnIndex: nextIndex,
      turnPhase: GameTurnPhase.rollDice,
      consecutiveSixes: 0,
      movablePawns: const [],
      statusMessage: '${state.players[nextIndex].name}\'s turn to roll!',
    );

    _checkBotTurn();
  }

  void _checkBotTurn() {
    if (state.isCurrentPlayerBot &&
        !state.isGameOver &&
        state.turnPhase == GameTurnPhase.rollDice) {
      _botTimer?.cancel();
      _botTimer = Timer(const Duration(milliseconds: 800), () {
        rollDice();
      });
    }
  }

  void _scheduleBotMove() {
    _botTimer?.cancel();
    _botTimer = Timer(const Duration(milliseconds: 700), () {
      final bestMove = GameEngine.selectBestBotMove(
        players: state.players,
        botPlayer: state.currentPlayer,
        movablePawns: state.movablePawns,
        diceValue: state.diceValue ?? 1,
      );
      if (bestMove != null) {
        movePawn(bestMove);
      }
    });
  }
}
