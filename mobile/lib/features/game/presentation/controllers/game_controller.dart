import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/dice_randomizer.dart';
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
  // Online turns include state delivery between two clients. Give the remote
  // player time to receive the turn and tap the die before auto-roll begins.
  static const Duration onlineTurnDuration = Duration(seconds: 15);
  static const int maxMissedTurns = 5;

  final math.Random _random = math.Random();
  final DiceRandomizer _diceRandomizer = DiceRandomizer();
  Timer? _botTimer;
  Timer? _turnTimer;
  Stopwatch? _turnStopwatch;
  Duration _turnTimeRemaining = turnDuration;
  String? _turnTimerPlayerId;
  Timer? _pawnSelectionTimer;
  Stopwatch? _pawnSelectionStopwatch;
  Duration _pawnSelectionTimeRemaining = turnDuration;
  String? _pawnSelectionTimerPlayerId;
  int? _pawnSelectionOpportunityId;
  GameState? _sixSequenceSnapshot;
  int _matchEpoch = 0;
  bool _isTurnProcessing = false;
  bool _isDisposed = false;
  bool _turnTimerPaused = false;
  bool _turnTimerDisabled = false;
  String? _onlineRoomId;
  String? _onlineLocalPlayerId;
  LudoColor? _onlineSelectedColor;
  Map<String, LudoColor> _onlineWireColorByPlayerId = const {};
  Map<String, String> _onlineViewColorByWireName = const {};
  Map<String, String> _onlineWireColorByViewName = const {};
  Future<int> Function(int rollOpportunityId)? _onlineDiceRoller;
  bool _applyingRemoteState = false;
  String _currentGameId = '';
  int _lastOnlineStateRevision = 0;

  GameNotifier() : super(const GameState(players: []));

  String? get onlineRoomId => _onlineRoomId;
  String? get onlineLocalPlayerId => _onlineLocalPlayerId;
  GameState get currentState => state;
  bool get isOnlineMode => _onlineRoomId != null;
  Duration get _activeTurnDuration =>
      isOnlineMode ? onlineTurnDuration : turnDuration;
  bool get isApplyingRemoteState => _applyingRemoteState;
  String get currentGameId => _currentGameId;

  void configureOnlineMatch({
    required String roomId,
    required String playerId,
    required LudoColor selectedColor,
    required Future<int> Function(int rollOpportunityId) requestDiceRoll,
  }) {
    _onlineRoomId = roomId;
    _onlineLocalPlayerId = playerId;
    _onlineSelectedColor = selectedColor;
    _onlineDiceRoller = requestDiceRoll;
    _lastOnlineStateRevision = 0;
    state = state.copyWith(localPlayerId: playerId);
  }

  void clearOnlineMatch() {
    _onlineRoomId = null;
    _onlineLocalPlayerId = null;
    _onlineDiceRoller = null;
    _onlineSelectedColor = null;
    _onlineWireColorByPlayerId = const {};
    _onlineViewColorByWireName = const {};
    _onlineWireColorByViewName = const {};
    _lastOnlineStateRevision = 0;
    state = state.copyWith(clearLocalPlayerId: true);
  }

  void applyRemoteGameState(Map<String, dynamic> json, {int? revision}) {
    if (!isOnlineMode) return;
    if (revision != null && revision <= _lastOnlineStateRevision) return;
    final perspectiveJson = _mapWireColors(json, _onlineViewColorByWireName);
    var remote = GameState.fromJson(perspectiveJson,
        localPlayerId: _onlineLocalPlayerId);
    if ((remote.players.length != 2 && remote.players.length != 4) ||
        remote.players.any((player) => player.isBot)) {
      return;
    }
    if (revision != null) _lastOnlineStateRevision = revision;
    // Keep a pawn that has reached the finish visible if an online state
    // update carries the completed move event before its pawn snapshot catches
    // up. The event and pawn colors have already been mapped to this client's
    // perspective above.
    final completedMove = remote.lastMoveEvent;
    if (completedMove?.toStep == 56) {
      remote = remote.copyWith(
        players: remote.players.map((player) {
          if (player.color != completedMove!.color) return player;
          return player.copyWith(
            pawns: player.pawns
                .map((pawn) => pawn.id == completedMove.pawnId &&
                        (pawn.isFinished ||
                            pawn.stepCount == completedMove.fromStep)
                    ? pawn.copyWith(stepCount: 56)
                    : pawn)
                .toList(growable: false),
          );
        }).toList(growable: false),
      );
    }
    _botTimer?.cancel();
    _cancelTurnTimer();
    _cancelPawnSelectionTimer();
    _matchEpoch++;
    _isTurnProcessing = false;
    _sixSequenceSnapshot = null;
    _turnTimeRemaining = Duration(
      milliseconds: remote.turnTimerRemainingMilliseconds,
    );
    _turnTimerDisabled = _turnTimerDisabled || remote.turnTimerDisabled;
    final synchronizedRemote = _turnTimerDisabled && !remote.turnTimerDisabled
        ? remote.copyWith(
            turnTimerDisabled: true,
            turnTimerRemainingMilliseconds: 0,
          )
        : remote;
    _pawnSelectionTimeRemaining = Duration(
      milliseconds: synchronizedRemote.turnTimerRemainingMilliseconds,
    );
    _applyingRemoteState = true;
    state = synchronizedRemote;
    _applyingRemoteState = false;

    if (synchronizedRemote.isGameOver ||
        synchronizedRemote.turnTimerDisabled ||
        synchronizedRemote.currentPlayer.id != _onlineLocalPlayerId) {
      return;
    }
    if (synchronizedRemote.turnPhase == GameTurnPhase.rollDice) {
      _scheduleTurnTimeout(Duration(
        milliseconds: synchronizedRemote.turnTimerRemainingMilliseconds,
      ));
    } else if (synchronizedRemote.turnPhase == GameTurnPhase.selectPawn &&
        synchronizedRemote.legalMovablePawns.length > 1) {
      _schedulePawnSelectionTimeoutWithRemaining(Duration(
        milliseconds: synchronizedRemote.turnTimerRemainingMilliseconds,
      ));
    }
  }

  Map<String, dynamic> toOnlineWireJson(GameState gameState) =>
      _mapWireColors(gameState.toJson(), _onlineWireColorByViewName);

  Map<String, dynamic> _mapWireColors(
    Map<String, dynamic> json,
    Map<String, String> mapping,
  ) {
    dynamic mapValue(dynamic value) {
      if (value is String) return mapping[value] ?? value;
      if (value is List) return value.map(mapValue).toList(growable: false);
      if (value is Map) {
        return <String, dynamic>{
          for (final entry in value.entries)
            (mapping[entry.key.toString()] ?? entry.key.toString()):
                mapValue(entry.value),
        };
      }
      return value;
    }

    return Map<String, dynamic>.from(mapValue(json) as Map);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _botTimer?.cancel();
    _cancelTurnTimer();
    _cancelPawnSelectionTimer();
    super.dispose();
  }

  /// Initializes a new Ludo Game (Vs Computer or Pass & Play)
  void startNewGame({
    required List<PlayerModel> players,
  }) {
    var gamePlayers = players;
    if (isOnlineMode &&
        players.length == 2 &&
        _onlineSelectedColor != null &&
        _onlineWireColorByPlayerId.isEmpty) {
      final local =
          players.where((player) => player.id == _onlineLocalPlayerId);
      if (local.isNotEmpty) {
        final localWireColor = local.first.color;
        final opponentWireColor = players
            .firstWhere((player) => player.id != _onlineLocalPlayerId)
            .color;
        final opponentViewColor = LudoColor.values[
            (_onlineSelectedColor!.index + 2) % LudoColor.values.length];
        _onlineWireColorByPlayerId = {
          for (final player in players) player.id: player.color,
        };
        _onlineViewColorByWireName = {
          localWireColor.name: _onlineSelectedColor!.name,
          opponentWireColor.name: opponentViewColor.name,
        };
        _onlineWireColorByViewName = {
          for (final entry in _onlineViewColorByWireName.entries)
            entry.value: entry.key,
        };
        gamePlayers = players
            .map((player) => player.copyWithColor(
                player.id == _onlineLocalPlayerId
                    ? _onlineSelectedColor!
                    : opponentViewColor))
            .toList(growable: false);
      }
    }
    _currentGameId =
        '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
    _botTimer?.cancel();
    _cancelTurnTimer();
    _cancelPawnSelectionTimer();
    _matchEpoch++;
    _isTurnProcessing = false;
    _turnTimerPaused = false;
    _turnTimerDisabled = false;
    _sixSequenceSnapshot = null;
    final freshPlayers = gamePlayers
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
    var startingTurnIndex = humanTurnIndex < 0 ? 0 : humanTurnIndex;
    if (isOnlineMode && freshPlayers.length >= 2) {
      // Matchmaking chooses the lexicographically first player as the initial
      // turn owner. Every client must construct the same initial game state.
      startingTurnIndex = 0;
      for (var index = 1; index < freshPlayers.length; index++) {
        if (freshPlayers[index]
                .id
                .compareTo(freshPlayers[startingTurnIndex].id) <
            0) {
          startingTurnIndex = index;
        }
      }
    }
    state = GameState(
      players: freshPlayers,
      localPlayerId: _onlineLocalPlayerId,
      currentTurnIndex: startingTurnIndex,
      turnPhase: GameTurnPhase.rollDice,
      isDiceRolling: false,
      rollOpportunityId: 0,
      turnTimerPaused: false,
      turnTimerDisabled: false,
      turnTimerRemainingMilliseconds: _activeTurnDuration.inMilliseconds,
      statusMessage: '${freshPlayers[startingTurnIndex].name}\'s turn to roll!',
    );

    _beginRollOpportunity();
  }

  /// Rolls the 6-sided dice with 3D animation simulation
  Future<void> rollDice({bool automatic = false}) async {
    if (_isDisposed ||
        (isOnlineMode && state.currentPlayer.id != _onlineLocalPlayerId) ||
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
    final rollOpportunityId = state.rollOpportunityId;
    final authoritativeDice =
        isOnlineMode ? _onlineDiceRoller?.call(rollOpportunityId) : null;
    if (isOnlineMode && authoritativeDice == null) {
      _isTurnProcessing = false;
      return;
    }

    state = state.copyWith(
      turnPhase: GameTurnPhase.animating,
      isDiceRolling: true,
      statusMessage: '${state.currentPlayer.name} is rolling...',
    );

    // Simulate dice rolling delay
    await Future.delayed(const Duration(milliseconds: 650));
    if (_isDisposed || matchEpoch != _matchEpoch) return;
    int diceResult;
    try {
      diceResult = authoritativeDice == null
          ? _diceRandomizer.roll()
          : await authoritativeDice;
    } catch (_) {
      if (_isDisposed || matchEpoch != _matchEpoch) return;
      _isTurnProcessing = false;
      state = state.copyWith(
        turnPhase: GameTurnPhase.rollDice,
        isDiceRolling: false,
        turnTimerPaused: false,
        turnTimerRemainingMilliseconds: _activeTurnDuration.inMilliseconds,
        statusMessage: 'Could not reach the game server. Tap to roll again.',
      );
      _scheduleTurnTimeout(_activeTurnDuration);
      return;
    }

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
        localPlayerId: _onlineLocalPlayerId,
        currentTurnIndex: snapshot?.currentTurnIndex ?? state.currentTurnIndex,
        diceValue: diceResult,
        lastRolledDiceValue: diceResult,
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
        turnTimerDisabled: _turnTimerDisabled,
        turnTimerRemainingMilliseconds: _activeTurnDuration.inMilliseconds,
        statusMessage: 'Three 6s! Moves reverted. Roll again.',
      );
      _beginRollOpportunity();
      return;
    }

    final movable = GameEngine.getMovablePawns(state.currentPlayer, diceResult);

    if (movable.isEmpty) {
      state = state.copyWith(
        diceValue: diceResult,
        lastRolledDiceValue: diceResult,
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
        lastRolledDiceValue: diceResult,
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
        turnTimerPaused: false,
        turnTimerRemainingMilliseconds: _activeTurnDuration.inMilliseconds,
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
      } else {
        _schedulePawnSelectionTimeout();
      }
    }
  }

  /// Moves the selected pawn along the Ludo track with step-by-step animation
  Future<void> movePawn(PawnModel selectedPawn) async {
    if (_isDisposed ||
        (isOnlineMode && state.currentPlayer.id != _onlineLocalPlayerId) ||
        _isTurnProcessing ||
        state.currentPlayer.isEliminated ||
        state.turnPhase != GameTurnPhase.selectPawn ||
        state.diceValue == null) {
      return;
    }
    if (!state.legalMovablePawns
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
    if (!GameEngine.isPawnMoveValid(pawn, dice)) return;
    final isYardMove = pawn.isYard;

    _cancelPawnSelectionTimer();

    final fromStep = pawn.stepCount;
    final newStepCount = isYardMove ? 0 : (fromStep + dice);

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

    // Check for reaching home after the five inner squares (step 56).
    final reachedHome = newStepCount == 56;
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
      clearLastCaptureEvent: captureEvent == null,
      winnerIds: newWinnerIds,
      // Keep controls active until the winning pawn's move animation lands.
      isGameOver: false,
      statusMessage: statusMsg,
    );

    // Keep the turn animating until both the selected pawn's move and any
    // captured pawn's return to its yard have completed.
    final moveAnimationSteps = moveEvent.stepsCount;
    final moveDurationMicroseconds = moveAnimationSteps * 130000;
    const captureFlameDurationMicroseconds = 620000;
    final captureReturnDurationMicroseconds =
        capturedPawn == null ? 0 : captureFlameDurationMicroseconds + 260000;
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
      clearDiceValue: true,
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
    _cancelPawnSelectionTimer();
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
      clearDiceValue: true,
      turnTimerPaused: _turnTimerPaused,
      turnTimerDisabled: _turnTimerDisabled,
      turnTimerRemainingMilliseconds: _activeTurnDuration.inMilliseconds,
    );

    if (isOnlineMode && state.currentPlayer.id != _onlineLocalPlayerId) return;

    if (_turnTimerPaused || _turnTimerDisabled) return;
    if (state.isCurrentPlayerBot) {
      _checkBotTurn();
    } else {
      _scheduleTurnTimeout(_activeTurnDuration);
    }
  }

  void _scheduleTurnTimeout(Duration delay) {
    if (_isDisposed ||
        state.isGameOver ||
        state.turnTimerPaused ||
        state.turnTimerDisabled ||
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
    _cancelPawnSelectionTimer();
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
      turnTimerRemainingMilliseconds: _activeTurnDuration.inMilliseconds,
      statusMessage: '${players[nextIndex].name} takes the next turn.',
    );
    _beginRollOpportunity();
  }

  /// Ends a two-player match immediately when its human player forfeits.
  bool forfeitHumanPlayer() {
    if (_isDisposed || state.isGameOver || state.players.length != 2) {
      return false;
    }

    final humanIndices = <int>[
      for (var i = 0; i < state.players.length; i++)
        if (!state.players[i].isBot &&
            !state.players[i].isEliminated &&
            !state.players[i].hasAllPawnsHome)
          i,
    ];
    final onlineForfeitingIndex = isOnlineMode
        ? state.players
            .indexWhere((player) => player.id == _onlineLocalPlayerId)
        : -1;
    if (isOnlineMode && onlineForfeitingIndex < 0) return false;
    final forfeitingIndex = isOnlineMode
        ? onlineForfeitingIndex
        : humanIndices.length == 1
            ? humanIndices.single
            : state.currentTurnIndex;
    final forfeitingPlayer = state.players[forfeitingIndex];
    final updatedPlayers = [...state.players];
    updatedPlayers[forfeitingIndex] = forfeitingPlayer.copyWith(
      isEliminated: true,
      eliminationOrder:
          state.players.where((player) => player.isEliminated).length + 1,
    );
    final winnerIndex = 1 - forfeitingIndex;
    final winner = updatedPlayers[winnerIndex];
    final winnerIds = List<String>.from(state.winnerIds);
    if (!winnerIds.contains(winner.id)) winnerIds.add(winner.id);
    updatedPlayers[winnerIndex] = winner.copyWith(rank: winnerIds.length);

    _cancelTurnTimer();
    _cancelPawnSelectionTimer();
    _botTimer?.cancel();
    _isTurnProcessing = false;
    state = state.copyWith(
      players: updatedPlayers,
      currentTurnIndex: winnerIndex,
      winnerIds: winnerIds,
      isGameOver: true,
      turnPhase: GameTurnPhase.turnEnded,
      movablePawns: const [],
      isDiceRolling: false,
      turnTimerPaused: false,
      turnTimerRemainingMilliseconds: 0,
      statusMessage: '${winner.name} wins by forfeit!',
    );
    return true;
  }

  bool forfeitDisconnectedOpponent(String opponentId) {
    if (_isDisposed ||
        !isOnlineMode ||
        state.isGameOver ||
        state.players.length != 2) {
      return false;
    }
    final opponentIndex = state.players.indexWhere(
      (player) => player.id == opponentId && !player.isEliminated,
    );
    final winnerIndex = state.players.indexWhere(
      (player) => player.id == _onlineLocalPlayerId && !player.isEliminated,
    );
    if (opponentIndex < 0 || winnerIndex < 0 || opponentIndex == winnerIndex) {
      return false;
    }

    final players = [...state.players];
    final eliminationOrder =
        players.where((player) => player.isEliminated).length + 1;
    players[opponentIndex] = players[opponentIndex].copyWith(
      isEliminated: true,
      eliminationOrder: eliminationOrder,
      rank: 2,
    );
    players[winnerIndex] = players[winnerIndex].copyWith(rank: 1);
    final winnerIds = [...state.winnerIds];
    if (!winnerIds.contains(players[winnerIndex].id)) {
      winnerIds.add(players[winnerIndex].id);
    }

    _cancelTurnTimer();
    _cancelPawnSelectionTimer();
    _botTimer?.cancel();
    _isTurnProcessing = false;
    _applyingRemoteState = true;
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
      statusMessage: '${players[winnerIndex].name} wins by forfeit!',
    );
    _applyingRemoteState = false;
    return true;
  }

  void _autoSelectAndMove(List<PawnModel> movable) {
    if (state.turnPhase != GameTurnPhase.selectPawn) return;
    final legalPawns = movable
        .where((pawn) => GameEngine.isPawnMoveValid(pawn, state.diceValue ?? 1))
        .toList(growable: false);
    final selectedPawn = GameEngine.selectBestBotMove(
          players: state.players,
          botPlayer: state.currentPlayer,
          movablePawns: legalPawns,
          diceValue: state.diceValue ?? 1,
        ) ??
        (legalPawns.isEmpty ? null : legalPawns.first);
    if (selectedPawn != null) {
      unawaited(movePawn(selectedPawn));
    } else {
      _continueAfterUnavailableMove();
    }
  }

  void _continueAfterUnavailableMove() {
    if (_isDisposed || state.turnPhase != GameTurnPhase.selectPawn) return;
    if (state.diceValue == 6) {
      state = state.copyWith(
        turnPhase: GameTurnPhase.rollDice,
        clearDiceValue: true,
        movablePawns: const [],
        consecutiveSixes: 0,
        statusMessage: 'No valid move. Bonus roll!',
      );
      _beginRollOpportunity();
    } else {
      _nextTurn();
    }
  }

  void _schedulePawnSelectionTimeout() {
    _schedulePawnSelectionTimeoutWithRemaining(_activeTurnDuration);
  }

  void _schedulePawnSelectionTimeoutWithRemaining(Duration delay) {
    _cancelPawnSelectionTimer();
    if (_isDisposed ||
        _isTurnProcessing ||
        state.isGameOver ||
        state.turnTimerPaused ||
        state.turnTimerDisabled ||
        (isOnlineMode && state.currentPlayer.id != _onlineLocalPlayerId) ||
        state.turnPhase != GameTurnPhase.selectPawn ||
        state.isCurrentPlayerBot ||
        state.currentPlayer.isEliminated ||
        state.legalMovablePawns.length < 2) {
      return;
    }

    final playerId = state.currentPlayer.id;
    final opportunityId = state.rollOpportunityId;
    _pawnSelectionTimerPlayerId = playerId;
    _pawnSelectionOpportunityId = opportunityId;
    _pawnSelectionTimeRemaining = delay;
    _pawnSelectionStopwatch = Stopwatch()..start();
    state = state.copyWith(
      turnTimerRemainingMilliseconds: delay.inMilliseconds,
    );
    _pawnSelectionTimer = Timer(delay, () {
      if (_isDisposed ||
          _pawnSelectionTimerPlayerId != playerId ||
          _pawnSelectionOpportunityId != opportunityId ||
          state.currentPlayer.id != playerId ||
          state.rollOpportunityId != opportunityId ||
          state.turnPhase != GameTurnPhase.selectPawn ||
          state.isGameOver ||
          _turnTimerPaused ||
          _isTurnProcessing) {
        return;
      }

      _pawnSelectionTimer = null;
      _pawnSelectionStopwatch = null;
      _pawnSelectionTimeRemaining = Duration.zero;
      final missedTurns = math.min(
        maxMissedTurns,
        state.currentPlayer.missedTurns + 1,
      );
      final players = state.players
          .map((player) => player.id == playerId
              ? player.copyWith(missedTurns: missedTurns)
              : player)
          .toList(growable: false);
      state = state.copyWith(
        players: players,
        turnTimerRemainingMilliseconds: 0,
        statusMessage: 'Time ran out! Moving a token automatically.',
      );
      final legalPawns = state.legalMovablePawns
          .where(
              (pawn) => GameEngine.isPawnMoveValid(pawn, state.diceValue ?? 1))
          .toList(growable: false);
      _autoSelectAndMove(legalPawns);
    });
  }

  void _cancelPawnSelectionTimer() {
    _pawnSelectionTimer?.cancel();
    _pawnSelectionTimer = null;
    _pawnSelectionStopwatch?.stop();
    _pawnSelectionStopwatch = null;
    _pawnSelectionTimerPlayerId = null;
    _pawnSelectionOpportunityId = null;
    _pawnSelectionTimeRemaining = _activeTurnDuration;
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
    if (_pawnSelectionTimer != null) {
      final elapsed = _pawnSelectionStopwatch?.elapsed ?? Duration.zero;
      _pawnSelectionTimeRemaining -= elapsed;
      if (_pawnSelectionTimeRemaining.isNegative) {
        _pawnSelectionTimeRemaining = Duration.zero;
      }
      _pawnSelectionTimer?.cancel();
      _pawnSelectionTimer = null;
      _pawnSelectionStopwatch?.stop();
      _pawnSelectionStopwatch = null;
    }
    _botTimer?.cancel();
    _turnTimerPaused = true;
    if (!_isDisposed && updateGameState) {
      state = state.copyWith(
        turnTimerPaused: true,
        turnTimerRemainingMilliseconds:
            (state.turnPhase == GameTurnPhase.selectPawn
                    ? _pawnSelectionTimeRemaining
                    : _turnTimeRemaining)
                .inMilliseconds,
      );
    }
  }

  void resumeTurnTimer() {
    if (!_turnTimerPaused || _isDisposed) return;
    _turnTimerPaused = false;
    if (state.isGameOver) {
      state = state.copyWith(turnTimerPaused: false);
      return;
    }
    state = state.copyWith(turnTimerPaused: false);
    if (isOnlineMode && state.currentPlayer.id != _onlineLocalPlayerId) return;
    if (state.turnPhase == GameTurnPhase.selectPawn) {
      if (state.isCurrentPlayerBot) {
        _scheduleBotMove();
      } else if (state.legalMovablePawns.length > 1) {
        _schedulePawnSelectionTimeoutWithRemaining(_pawnSelectionTimeRemaining);
      }
      return;
    }
    if (state.turnTimerDisabled || state.turnPhase != GameTurnPhase.rollDice) {
      return;
    }
    if (state.isCurrentPlayerBot) {
      _checkBotTurn();
    } else {
      _scheduleTurnTimeout(_turnTimeRemaining);
    }
  }

  void disableTurnTimerForFriendlyChat() {
    if (!isOnlineMode || state.isGameOver || _turnTimerDisabled) return;
    _turnTimerDisabled = true;
    _cancelTurnTimer();
    _cancelPawnSelectionTimer();
    _botTimer?.cancel();
    if (_isDisposed) return;
    state = state.copyWith(
      turnTimerDisabled: true,
      turnTimerRemainingMilliseconds: 0,
    );
  }

  void _cancelTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
    _turnStopwatch?.stop();
    _turnStopwatch = null;
    _turnTimerPlayerId = null;
    _turnTimeRemaining = _activeTurnDuration;
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
    if (_isDisposed ||
        _turnTimerPaused ||
        state.isGameOver ||
        !state.isCurrentPlayerBot ||
        state.turnPhase != GameTurnPhase.selectPawn) {
      return;
    }
    final matchEpoch = _matchEpoch;
    final playerId = state.currentPlayer.id;
    final opportunityId = state.rollOpportunityId;
    _botTimer = Timer(const Duration(milliseconds: 700), () {
      if (_isDisposed ||
          matchEpoch != _matchEpoch ||
          state.currentPlayer.id != playerId ||
          state.rollOpportunityId != opportunityId ||
          state.turnTimerPaused ||
          state.turnPhase != GameTurnPhase.selectPawn) {
        return;
      }
      _botTimer = null;
      _autoSelectAndMove(state.legalMovablePawns);
    });
  }
}
