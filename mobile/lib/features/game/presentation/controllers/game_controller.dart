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
  static const Duration turnDuration = Duration(seconds: 5);
  static const int maxMissedTurns = 5;

  final math.Random _random = math.Random();
  Timer? _botTimer;
  Timer? _turnTimer;
  Stopwatch? _turnStopwatch;
  Duration _turnTimeRemaining = turnDuration;
  String? _turnTimerPlayerId;
  GameState? _sixSequenceSnapshot;
  int _matchEpoch = 0;
  bool _isTurnProcessing = false;
  bool _isDisposed = false;
  bool _turnTimerPaused = false;

  GameNotifier() : super(const GameState(players: []));

  @override
  void dispose() {
    _isDisposed = true;
    _botTimer?.cancel();
    _cancelTurnTimer();
    super.dispose();
  }

  /// Initializes a new Ludo Game (Vs Computer or Pass & Play)
  void startNewGame({
    required List<PlayerModel> players,
  }) {
    _botTimer?.cancel();
    _cancelTurnTimer();
    _matchEpoch++;
    _isTurnProcessing = false;
    _turnTimerPaused = false;
    _sixSequenceSnapshot = null;
    final freshPlayers = players
        .map(
          (player) => PlayerModel.initial(
            id: player.id,
            name: player.name,
            avatarUrl: player.avatarUrl,
            country: player.country,
            countryFlag: player.countryFlag,
            coins: player.coins,
            diamonds: player.diamonds,
            color: player.color,
            isBot: player.isBot,
          ),
        )
        .toList();
    final humanTurnIndex = freshPlayers.indexWhere((player) => !player.isBot);
    final startingTurnIndex = humanTurnIndex < 0 ? 0 : humanTurnIndex;
    state = GameState(
      players: freshPlayers,
      currentTurnIndex: startingTurnIndex,
      turnPhase: GameTurnPhase.rollDice,
      isDiceRolling: false,
      rollOpportunityId: state.rollOpportunityId,
      turnTimerPaused: false,
      turnTimerRemainingMilliseconds: turnDuration.inMilliseconds,
      statusMessage: '${freshPlayers[startingTurnIndex].name}\'s turn to roll!',
    );

    _beginRollOpportunity();
  }

  /// Rolls the 6-sided dice with 3D animation simulation
  Future<void> rollDice({bool automatic = false}) async {
    if (_isDisposed ||
        _isTurnProcessing ||
        state.turnPhase != GameTurnPhase.rollDice ||
        state.isGameOver ||
        state.turnTimerPaused ||
        state.currentPlayer.isEliminated) {
      return;
    }

    _cancelTurnTimer();
    _botTimer?.cancel();
    _isTurnProcessing = true;
    final matchEpoch = _matchEpoch;

    state = state.copyWith(
      turnPhase: GameTurnPhase.animating,
      isDiceRolling: true,
      statusMessage: '${state.currentPlayer.name} is rolling...',
    );

    // Simulate dice rolling delay
    await Future.delayed(const Duration(milliseconds: 650));
    if (_isDisposed || matchEpoch != _matchEpoch) return;
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
      final missedTurnsByPlayerId = {
        for (final player in state.players) player.id: player.missedTurns,
      };
      final rollbackPlayers = (snapshot?.players ?? state.players)
          .map((player) => player.copyWith(
                missedTurns:
                    missedTurnsByPlayerId[player.id] ?? player.missedTurns,
              ))
          .toList(growable: false);
      state = GameState(
        players: rollbackPlayers,
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
        rollOpportunityId: state.rollOpportunityId,
        turnTimerPaused: false,
        turnTimerRemainingMilliseconds: turnDuration.inMilliseconds,
        statusMessage: 'Three 6s! Moves reverted. Roll again.',
      );
      _beginRollOpportunity();
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
      if (_isDisposed || matchEpoch != _matchEpoch) return;
      if (diceResult == 6) {
        // Bonus roll if 6 rolled, otherwise next player
        state = state.copyWith(
          turnPhase: GameTurnPhase.rollDice,
          statusMessage: 'Bonus roll for 6!',
        );
        _beginRollOpportunity();
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
      _isTurnProcessing = false;

      // Auto-move for Bot
      if (state.isCurrentPlayerBot) {
        _scheduleBotMove();
      } else if (automatic) {
        _autoSelectAndMove(movable);
      } else if (movable.length == 1) {
        // No choice is needed when only one pawn can legally move.
        await movePawn(movable.single);
      }
    }
  }

  /// Moves the selected pawn along the Ludo track with step-by-step animation
  Future<void> movePawn(PawnModel selectedPawn) async {
    if (_isDisposed ||
        _isTurnProcessing ||
        state.currentPlayer.isEliminated ||
        state.turnPhase != GameTurnPhase.selectPawn ||
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

    _isTurnProcessing = true;
    final matchEpoch = _matchEpoch;

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
    final reachedHome = newStepCount == 57;
    if (reachedHome) {
      earnedBonusRoll = true; // Achievement reward for completing a pawn.
    }

    // Apply pawn moves and captures to players list
    var updatedPlayers = state.players.map((p) {
      if (p.color == player.color) {
        final newPawns = p.pawns
            .map((candidate) =>
                candidate.id == pawn.id ? updatedPawn : candidate)
            .toList();
        final newKillCounts = Map<LudoColor, int>.from(p.killCounts);
        if (capturedColor != null) {
          newKillCounts.update(
            capturedColor,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        return p.copyWith(pawns: newPawns, killCounts: newKillCounts);
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
    int? achievedRank;

    if (updatedCurrentPlayer.hasAllPawnsHome &&
        !newWinnerIds.contains(updatedCurrentPlayer.id)) {
      newWinnerIds.add(updatedCurrentPlayer.id);
      achievedRank = newWinnerIds.length;
      updatedPlayers = updatedPlayers
          .map((finishedPlayer) => finishedPlayer.id == updatedCurrentPlayer.id
              ? finishedPlayer.copyWith(rank: achievedRank)
              : finishedPlayer)
          .toList();
    }

    final activePlayerCount =
        updatedPlayers.where((candidate) => !candidate.isEliminated).length;
    final isGameOver = updatedPlayers.length == 2
        ? newWinnerIds.isNotEmpty
        : newWinnerIds.length >= activePlayerCount;
    if (isGameOver && updatedPlayers.length == 2) {
      updatedPlayers = updatedPlayers
          .map((finishedPlayer) => finishedPlayer.rank == 0
              ? finishedPlayer.copyWith(rank: 2)
              : finishedPlayer)
          .toList();
    }

    String statusMsg = capturedPawn != null
        ? '${player.name} captured a token! Extra turn.'
        : achievedRank != null
            ? '${player.name} takes rank $achievedRank!'
            : reachedHome
                ? '${player.name} reached HOME! Achievement unlocked: extra roll.'
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
      // Keep controls active until the winning pawn's move animation lands.
      isGameOver: false,
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
    const captureFlameDurationMicroseconds = 620000;
    final captureReturnDurationMicroseconds = capturedPawn == null
        ? 0
        : captureFlameDurationMicroseconds + captureDurationMicroseconds;
    final animDurationMicroseconds = math
            .max(moveDurationMicroseconds, captureReturnDurationMicroseconds)
            .toInt() +
        200000;
    await Future.delayed(
      Duration(microseconds: animDurationMicroseconds),
    );
    if (_isDisposed || matchEpoch != _matchEpoch) return;

    if (isGameOver) {
      state = state.copyWith(
        isGameOver: true,
        turnPhase: GameTurnPhase.turnEnded,
        statusMessage:
            '${updatedPlayers.firstWhere((p) => p.id == newWinnerIds.first).name} wins!',
      );
      _isTurnProcessing = false;
      _cancelTurnTimer();
      return;
    }

    if (achievedRank != null) {
      _nextTurn();
    } else if (earnedBonusRoll) {
      state = state.copyWith(
        turnPhase: GameTurnPhase.rollDice,
      );
      _beginRollOpportunity();
    } else {
      _nextTurn();
    }
  }

  void _nextTurn() {
    _sixSequenceSnapshot = null;
    final nextIndex =
        _findNextActivePlayer(state.players, state.currentTurnIndex);
    if (nextIndex == null) {
      _cancelTurnTimer();
      _isTurnProcessing = false;
      state = state.copyWith(
        isGameOver: true,
        turnPhase: GameTurnPhase.turnEnded,
        statusMessage: 'Game over.',
      );
      return;
    }

    state = state.copyWith(
      currentTurnIndex: nextIndex,
      turnPhase: GameTurnPhase.rollDice,
      consecutiveSixes: 0,
      movablePawns: const [],
      statusMessage: '${state.players[nextIndex].name}\'s turn to roll!',
    );

    _beginRollOpportunity();
  }

  int? _findNextActivePlayer(List<PlayerModel> players, int currentIndex) {
    for (var offset = 1; offset <= players.length; offset++) {
      final index = (currentIndex + offset) % players.length;
      final player = players[index];
      if (!player.isEliminated && !player.hasAllPawnsHome) return index;
    }
    return null;
  }

  void _beginRollOpportunity() {
    _cancelTurnTimer();
    _botTimer?.cancel();
    _isTurnProcessing = false;
    if (_isDisposed ||
        state.isGameOver ||
        state.turnPhase != GameTurnPhase.rollDice ||
        state.currentPlayer.isEliminated) {
      return;
    }

    state = state.copyWith(
      rollOpportunityId: state.rollOpportunityId + 1,
      turnTimerPaused: _turnTimerPaused,
      turnTimerRemainingMilliseconds: turnDuration.inMilliseconds,
    );
    if (_turnTimerPaused) return;
    if (state.isCurrentPlayerBot) {
      _checkBotTurn();
    } else {
      _scheduleTurnTimeout(turnDuration);
    }
  }

  void _scheduleTurnTimeout(Duration delay) {
    if (_isDisposed ||
        state.isGameOver ||
        state.turnTimerPaused ||
        state.turnPhase != GameTurnPhase.rollDice ||
        state.isCurrentPlayerBot) {
      return;
    }
    final playerId = state.currentPlayer.id;
    final opportunityId = state.rollOpportunityId;
    _turnTimerPlayerId = playerId;
    _turnTimeRemaining = delay;
    _turnStopwatch = Stopwatch()..start();
    if (state.turnTimerRemainingMilliseconds != delay.inMilliseconds) {
      state = state.copyWith(
        turnTimerRemainingMilliseconds: delay.inMilliseconds,
      );
    }
    _turnTimer = Timer(delay, () {
      if (_turnTimerPlayerId != playerId ||
          state.currentPlayer.id != playerId ||
          state.rollOpportunityId != opportunityId ||
          state.turnPhase != GameTurnPhase.rollDice ||
          state.isGameOver ||
          _turnTimerPaused ||
          _isTurnProcessing) {
        return;
      }
      _turnTimer = null;
      _turnStopwatch = null;
      _turnTimeRemaining = Duration.zero;
      state = state.copyWith(turnTimerRemainingMilliseconds: 0);
      _recordMissedTurnAndRoll(playerId, opportunityId);
    });
  }

  void _recordMissedTurnAndRoll(String playerId, int opportunityId) {
    if (_isDisposed ||
        _isTurnProcessing ||
        state.currentPlayer.id != playerId ||
        state.rollOpportunityId != opportunityId ||
        state.turnPhase != GameTurnPhase.rollDice ||
        state.isGameOver) {
      return;
    }

    final missedTurns = math.min(
      maxMissedTurns,
      state.currentPlayer.missedTurns + 1,
    );
    final eliminationOrder =
        state.players.where((player) => player.isEliminated).length + 1;
    final updatedPlayers = state.players
        .map((player) => player.id == playerId
            ? player.copyWith(
                missedTurns: missedTurns,
                isEliminated: missedTurns >= maxMissedTurns,
                eliminationOrder: missedTurns >= maxMissedTurns
                    ? eliminationOrder
                    : player.eliminationOrder,
              )
            : player)
        .toList();

    if (missedTurns >= maxMissedTurns) {
      _eliminatePlayer(updatedPlayers, state.currentTurnIndex);
      return;
    }

    state = state.copyWith(players: updatedPlayers);
    // Uses the same guarded dice entry point as a manual tap.
    unawaited(rollDice(automatic: true));
  }

  void _eliminatePlayer(List<PlayerModel> players, int eliminatedIndex) {
    _cancelTurnTimer();
    _botTimer?.cancel();
    _isTurnProcessing = true;
    final remainingIndices = <int>[
      for (var i = 0; i < players.length; i++)
        if (!players[i].isEliminated && !players[i].hasAllPawnsHome) i,
    ];
    final winnerIds = List<String>.from(state.winnerIds);

    if (remainingIndices.length == 1) {
      final winnerIndex = remainingIndices.single;
      final winner = players[winnerIndex];
      if (!winnerIds.contains(winner.id)) winnerIds.add(winner.id);
      players[winnerIndex] = winner.copyWith(rank: winnerIds.length);
      state = state.copyWith(
        players: players,
        currentTurnIndex: winnerIndex,
        winnerIds: winnerIds,
        isGameOver: true,
        turnPhase: GameTurnPhase.turnEnded,
        movablePawns: const [],
        isDiceRolling: false,
        turnTimerPaused: false,
        turnTimerRemainingMilliseconds: 0,
        statusMessage: '${winner.name} wins by elimination!',
      );
      _isTurnProcessing = false;
      return;
    }

    final nextIndex = _findNextActivePlayer(players, eliminatedIndex);
    if (nextIndex == null) {
      state = state.copyWith(
        players: players,
        winnerIds: winnerIds,
        isGameOver: true,
        turnPhase: GameTurnPhase.turnEnded,
        movablePawns: const [],
        isDiceRolling: false,
        turnTimerPaused: false,
        turnTimerRemainingMilliseconds: 0,
        statusMessage: 'Game over.',
      );
      _isTurnProcessing = false;
      return;
    }

    state = state.copyWith(
      players: players,
      currentTurnIndex: nextIndex,
      winnerIds: winnerIds,
      isGameOver: false,
      turnPhase: GameTurnPhase.rollDice,
      clearDiceValue: true,
      consecutiveSixes: 0,
      movablePawns: const [],
      isDiceRolling: false,
      turnTimerPaused: false,
      turnTimerRemainingMilliseconds: turnDuration.inMilliseconds,
      statusMessage: '${players[nextIndex].name} takes the next turn.',
    );
    _beginRollOpportunity();
  }

  void _autoSelectAndMove(List<PawnModel> movable) {
    if (movable.isEmpty || state.turnPhase != GameTurnPhase.selectPawn) return;
    final selectedPawn = GameEngine.selectBestBotMove(
      players: state.players,
      botPlayer: state.currentPlayer,
      movablePawns: movable,
      diceValue: state.diceValue ?? 1,
    );
    if (selectedPawn != null) unawaited(movePawn(selectedPawn));
  }

  void pauseTurnTimer({bool updateGameState = true}) {
    if (_turnTimerPaused) return;
    if (_turnTimer != null) {
      final elapsed = _turnStopwatch?.elapsed ?? Duration.zero;
      _turnTimeRemaining = _turnTimeRemaining - elapsed;
      if (_turnTimeRemaining.isNegative) _turnTimeRemaining = Duration.zero;
      _turnTimer?.cancel();
      _turnTimer = null;
      _turnStopwatch?.stop();
      _turnStopwatch = null;
    }
    _botTimer?.cancel();
    _turnTimerPaused = true;
    if (!_isDisposed && updateGameState) {
      state = state.copyWith(
        turnTimerPaused: true,
        turnTimerRemainingMilliseconds: _turnTimeRemaining.inMilliseconds,
      );
    }
  }

  void resumeTurnTimer() {
    if (!_turnTimerPaused || _isDisposed) return;
    _turnTimerPaused = false;
    if (state.turnPhase != GameTurnPhase.rollDice || state.isGameOver) {
      state = state.copyWith(turnTimerPaused: false);
      return;
    }
    state = state.copyWith(turnTimerPaused: false);
    if (state.isCurrentPlayerBot) {
      _checkBotTurn();
    } else {
      _scheduleTurnTimeout(_turnTimeRemaining);
    }
  }

  void _cancelTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
    _turnStopwatch?.stop();
    _turnStopwatch = null;
    _turnTimerPlayerId = null;
    _turnTimeRemaining = turnDuration;
  }

  void _checkBotTurn() {
    if (state.isCurrentPlayerBot &&
        !state.isGameOver &&
        state.turnPhase == GameTurnPhase.rollDice) {
      _botTimer?.cancel();
      final matchEpoch = _matchEpoch;
      final playerId = state.currentPlayer.id;
      final opportunityId = state.rollOpportunityId;
      _botTimer = Timer(const Duration(milliseconds: 800), () {
        if (_isDisposed ||
            matchEpoch != _matchEpoch ||
            state.currentPlayer.id != playerId ||
            state.rollOpportunityId != opportunityId) {
          return;
        }
        unawaited(rollDice());
      });
    }
  }

  void _scheduleBotMove() {
    _botTimer?.cancel();
    final matchEpoch = _matchEpoch;
    final playerId = state.currentPlayer.id;
    _botTimer = Timer(const Duration(milliseconds: 700), () {
      if (_isDisposed ||
          matchEpoch != _matchEpoch ||
          state.currentPlayer.id != playerId ||
          state.turnPhase != GameTurnPhase.selectPawn) {
        return;
      }
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
