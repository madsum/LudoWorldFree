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
    final humanTurnIndex = players.indexWhere((player) => !player.isBot);
    final startingTurnIndex = humanTurnIndex < 0 ? 0 : humanTurnIndex;
    state = GameState(
      players: players,
      currentTurnIndex: startingTurnIndex,
      turnPhase: GameTurnPhase.rollDice,
      statusMessage: '${players[startingTurnIndex].name}\'s turn to roll!',
    );

    _checkBotTurn();
  }

  /// Rolls the 6-sided dice with 3D animation simulation
  Future<void> rollDice() async {
    if (state.turnPhase != GameTurnPhase.rollDice || state.isGameOver) return;

    state = state.copyWith(
      turnPhase: GameTurnPhase.animating,
      statusMessage: '${state.currentPlayer.name} is rolling...',
    );

    // Simulate dice rolling delay
    await Future.delayed(const Duration(milliseconds: 350));
    final diceResult = _random.nextInt(6) + 1;

    int consecutive6 = state.diceValue == 6 ? state.consecutiveSixes + 1 : 0;

    // Rule: 3 consecutive 6s penalty
    if (consecutive6 == 3) {
      state = state.copyWith(
        diceValue: diceResult,
        consecutiveSixes: 0,
        turnPhase: GameTurnPhase.turnEnded,
        statusMessage: 'Three 6s rolled! Turn forfeited.',
      );
      await Future.delayed(const Duration(milliseconds: 800));
      _nextTurn();
      return;
    }

    final movable = GameEngine.getMovablePawns(state.currentPlayer, diceResult);

    if (movable.isEmpty) {
      state = state.copyWith(
        diceValue: diceResult,
        consecutiveSixes: consecutive6,
        turnPhase: GameTurnPhase.turnEnded,
        movablePawns: const [],
        statusMessage: 'No valid moves for $diceResult.',
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
        consecutiveSixes: consecutive6,
        movablePawns: movable,
        turnPhase: GameTurnPhase.selectPawn,
        statusMessage: '${state.currentPlayer.name} rolled a $diceResult! Select a token.',
      );

      // Auto-move for Bot
      if (state.isCurrentPlayerBot) {
        _scheduleBotMove();
      }
    }
  }

  /// Moves the selected pawn along the Ludo track with step-by-step animation
  Future<void> movePawn(PawnModel selectedPawn) async {
    if (state.turnPhase != GameTurnPhase.selectPawn || state.diceValue == null) return;
    if (!state.movablePawns.any((p) => p.id == selectedPawn.id && p.color == selectedPawn.color)) {
      return;
    }

    final dice = state.diceValue!;
    final player = state.currentPlayer;
    final isYardMove = selectedPawn.isYard;

    final fromStep = selectedPawn.stepCount;
    final newStepCount = isYardMove ? 0 : (fromStep + dice);

    final moveEvent = PawnMoveEvent(
      color: selectedPawn.color,
      pawnId: selectedPawn.id,
      fromStep: fromStep,
      toStep: newStepCount,
    );

    final updatedPawn = selectedPawn.copyWith(stepCount: newStepCount);
    bool earnedBonusRoll = dice == 6;

    // Check for Capture / Cutting of opponent pawn
    PawnModel? capturedPawn;
    LudoColor? capturedColor;

    if (!isYardMove && newStepCount <= 50) {
      capturedPawn = GameEngine.findCapturableOpponentPawn(
        players: state.players,
        currentPlayerColor: player.color,
        targetStep: newStepCount,
      );
      if (capturedPawn != null) {
        capturedColor = capturedPawn.color;
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
        final newPawns = p.pawns.map((pawn) => pawn.id == selectedPawn.id ? updatedPawn : pawn).toList();
        return p.copyWith(pawns: newPawns);
      } else if (capturedColor != null && p.color == capturedColor) {
        final newPawns = p.pawns.map((pawn) => pawn.id == capturedPawn!.id ? pawn.copyWith(stepCount: -1) : pawn).toList();
        return p.copyWith(pawns: newPawns);
      }
      return p;
    }).toList();

    // Check player completion / ranking
    final updatedCurrentPlayer = updatedPlayers.firstWhere((p) => p.color == player.color);
    List<String> newWinnerIds = List.from(state.winnerIds);

    if (updatedCurrentPlayer.hasAllPawnsHome && !newWinnerIds.contains(updatedCurrentPlayer.id)) {
      newWinnerIds.add(updatedCurrentPlayer.id);
    }

    final isGameOver = newWinnerIds.length >= (updatedPlayers.length - 1);

    String statusMsg = capturedPawn != null
        ? '${player.name} captured an opponent token! Bonus roll!'
        : newStepCount == 57
            ? '${player.name} brought a token HOME! Bonus roll!'
            : earnedBonusRoll
                ? '${player.name} rolled a 6! Bonus roll!'
                : '${player.name} moved token.';

    // Emit animating phase and move event to presentation layer
    state = state.copyWith(
      players: updatedPlayers,
      turnPhase: GameTurnPhase.animating,
      movablePawns: const [],
      lastMoveEvent: moveEvent,
      winnerIds: newWinnerIds,
      isGameOver: isGameOver,
      statusMessage: statusMsg,
    );

    // Calculate animation duration based on steps count (130ms per step + 200ms settling)
    final animDurationMs = moveEvent.stepsCount * 130 + 200;
    await Future.delayed(Duration(milliseconds: animDurationMs));

    if (isGameOver) {
      state = state.copyWith(
        turnPhase: GameTurnPhase.turnEnded,
        statusMessage: '🎉 Game Over! ${newWinnerIds.first} wins!',
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
    if (state.isCurrentPlayerBot && !state.isGameOver && state.turnPhase == GameTurnPhase.rollDice) {
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
