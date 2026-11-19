import 'ludo_color.dart';
import '../game_engine.dart';
import 'pawn_model.dart';
import 'player_model.dart';

enum GameTurnPhase { rollDice, selectPawn, animating, turnEnded }

class PawnMoveEvent {
  final LudoColor color;
  final int pawnId;
  final int fromStep;
  final int toStep;
  final DateTime timestamp;

  PawnMoveEvent({
    required this.color,
    required this.pawnId,
    required this.fromStep,
    required this.toStep,
  }) : timestamp = DateTime.now();

  int get stepsCount => (fromStep == -1) ? 1 : (toStep - fromStep).abs();
}

class PawnCaptureEvent {
  final LudoColor color;
  final int pawnId;
  final int globalTrackIndex;
  final DateTime timestamp;

  PawnCaptureEvent({
    required this.color,
    required this.pawnId,
    required this.globalTrackIndex,
  }) : timestamp = DateTime.now();
}

class GameState {
  final List<PlayerModel> players;
  final String? localPlayerId;
  final int currentTurnIndex;
  final int? diceValue;
  final int? lastRolledDiceValue;
  final Map<String, int> playerDiceValues;
  final GameTurnPhase turnPhase;
  final int consecutiveSixes;
  final bool isDiceRolling;
  final List<PawnModel> movablePawns;
  final PawnMoveEvent? lastMoveEvent;
  final PawnCaptureEvent? lastCaptureEvent;
  final bool isGameOver;
  final List<String> winnerIds;
  final String statusMessage;
  final int rollOpportunityId;
  final bool turnTimerPaused;
  final bool turnTimerDisabled;
  final int turnTimerRemainingMilliseconds;

  const GameState({
    required this.players,
    this.localPlayerId,
    this.currentTurnIndex = 0,
    this.diceValue,
    this.lastRolledDiceValue,
    this.playerDiceValues = const {},
    this.turnPhase = GameTurnPhase.rollDice,
    this.consecutiveSixes = 0,
    this.isDiceRolling = false,
    this.movablePawns = const [],
    this.lastMoveEvent,
    this.lastCaptureEvent,
    this.isGameOver = false,
    this.winnerIds = const [],
    this.statusMessage = 'Roll the dice to start!',
    this.rollOpportunityId = 0,
    this.turnTimerPaused = false,
    this.turnTimerDisabled = false,
    this.turnTimerRemainingMilliseconds = 5000,
  });

  PlayerModel get currentPlayer => players[currentTurnIndex];
  bool get isCurrentPlayerBot => currentPlayer.isBot;
  bool get isLocalPlayerTurn =>
      localPlayerId == null || currentPlayer.id == localPlayerId;

  /// Recomputes the selectable pawns from the active player and die result.
  /// The serialized [movablePawns] list is useful for syncing older clients,
  /// but can be stale or incomplete in an online state update. Keep the board,
  /// tap validation, and turn timers on the same canonical set of legal moves.
  List<PawnModel> get legalMovablePawns {
    if (turnPhase != GameTurnPhase.selectPawn ||
        diceValue == null ||
        players.isEmpty) {
      return const [];
    }
    return GameEngine.getMovablePawns(currentPlayer, diceValue!);
  }

  Map<String, dynamic> toJson() => {
        'players': players.map(_playerToJson).toList(growable: false),
        'currentTurnIndex': currentTurnIndex,
        'diceValue': diceValue,
        'lastRolledDiceValue': lastRolledDiceValue,
        'playerDiceValues': playerDiceValues,
        'turnPhase': turnPhase.name,
        'consecutiveSixes': consecutiveSixes,
        'isDiceRolling': isDiceRolling,
        'movablePawns': movablePawns
            .map((pawn) => {'id': pawn.id, 'color': pawn.color.name})
            .toList(growable: false),
        'lastMoveEvent': lastMoveEvent == null
            ? null
            : {
                'color': lastMoveEvent!.color.name,
                'pawnId': lastMoveEvent!.pawnId,
                'fromStep': lastMoveEvent!.fromStep,
                'toStep': lastMoveEvent!.toStep,
              },
        'lastCaptureEvent': lastCaptureEvent == null
            ? null
            : {
                'color': lastCaptureEvent!.color.name,
                'pawnId': lastCaptureEvent!.pawnId,
                'globalTrackIndex': lastCaptureEvent!.globalTrackIndex,
              },
        'isGameOver': isGameOver,
        'winnerIds': winnerIds,
        'statusMessage': statusMessage,
        'rollOpportunityId': rollOpportunityId,
        'turnTimerPaused': turnTimerPaused,
        'turnTimerDisabled': turnTimerDisabled,
        'turnTimerRemainingMilliseconds': turnTimerRemainingMilliseconds,
      };

  factory GameState.fromJson(
    Map<String, dynamic> json, {
    String? localPlayerId,
  }) {
    final players = (json['players'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((player) => _playerFromJson(Map<String, dynamic>.from(player)))
        .toList(growable: false);
    final playerDiceValues = <String, int>{};
    if (json['playerDiceValues'] is Map) {
      (json['playerDiceValues'] as Map).forEach((key, value) {
        if (value is num) playerDiceValues[key.toString()] = value.toInt();
      });
    }
    final movablePawns = <PawnModel>[];
    for (final entry in (json['movablePawns'] as List<dynamic>? ?? const [])) {
      if (entry is! Map) continue;
      final color = _colorFromJson(entry['color']);
      final id = (entry['id'] as num?)?.toInt();
      if (color == null || id == null) continue;
      final player = players.where((candidate) => candidate.color == color);
      if (player.isEmpty) continue;
      final pawn = player.first.pawns.where((candidate) => candidate.id == id);
      if (pawn.isNotEmpty) movablePawns.add(pawn.first);
    }
    final move = json['lastMoveEvent'] is Map
        ? Map<String, dynamic>.from(json['lastMoveEvent'] as Map)
        : null;
    final capture = json['lastCaptureEvent'] is Map
        ? Map<String, dynamic>.from(json['lastCaptureEvent'] as Map)
        : null;
    final turnIndex = (json['currentTurnIndex'] as num?)?.toInt() ?? 0;
    return GameState(
      players: players,
      localPlayerId: localPlayerId,
      currentTurnIndex:
          players.isEmpty ? 0 : turnIndex.clamp(0, players.length - 1),
      diceValue: (json['diceValue'] as num?)?.toInt(),
      lastRolledDiceValue: (json['lastRolledDiceValue'] as num?)?.toInt() ??
          (json['diceValue'] as num?)?.toInt(),
      playerDiceValues: playerDiceValues,
      turnPhase: GameTurnPhase.values.firstWhere(
        (phase) => phase.name == json['turnPhase'],
        orElse: () => GameTurnPhase.rollDice,
      ),
      consecutiveSixes: (json['consecutiveSixes'] as num?)?.toInt() ?? 0,
      isDiceRolling: json['isDiceRolling'] == true,
      movablePawns: movablePawns,
      lastMoveEvent: move == null || _colorFromJson(move['color']) == null
          ? null
          : PawnMoveEvent(
              color: _colorFromJson(move['color'])!,
              pawnId: (move['pawnId'] as num?)?.toInt() ?? 0,
              fromStep: (move['fromStep'] as num?)?.toInt() ?? -1,
              toStep: (move['toStep'] as num?)?.toInt() ?? -1,
            ),
      lastCaptureEvent:
          capture == null || _colorFromJson(capture['color']) == null
              ? null
              : PawnCaptureEvent(
                  color: _colorFromJson(capture['color'])!,
                  pawnId: (capture['pawnId'] as num?)?.toInt() ?? 0,
                  globalTrackIndex:
                      (capture['globalTrackIndex'] as num?)?.toInt() ?? 0,
                ),
      isGameOver: json['isGameOver'] == true,
      winnerIds: (json['winnerIds'] as List<dynamic>? ?? const [])
          .map((id) => id.toString())
          .toList(growable: false),
      statusMessage: json['statusMessage']?.toString() ?? '',
      rollOpportunityId: (json['rollOpportunityId'] as num?)?.toInt() ?? 0,
      turnTimerPaused: json['turnTimerPaused'] == true,
      turnTimerDisabled: json['turnTimerDisabled'] == true,
      turnTimerRemainingMilliseconds:
          (json['turnTimerRemainingMilliseconds'] as num?)?.toInt() ?? 5000,
    );
  }

  static Map<String, dynamic> _playerToJson(PlayerModel player) => {
        'id': player.id,
        'name': player.name,
        'avatarUrl': player.avatarUrl,
        'country': player.country,
        'countryFlag': player.countryFlag,
        'coins': player.coins,
        'diamonds': player.diamonds,
        'color': player.color.name,
        'isBot': player.isBot,
        'pawns': player.pawns
            .map((pawn) => {
                  'id': pawn.id,
                  'color': pawn.color.name,
                  'stepCount': pawn.stepCount,
                  'pairId': pawn.pairId,
                  'isPairSelected': pawn.isPairSelected,
                })
            .toList(growable: false),
        'rank': player.rank,
        'killCounts': {
          for (final entry in player.killCounts.entries)
            entry.key.name: entry.value,
        },
        'missedTurns': player.missedTurns,
        'isEliminated': player.isEliminated,
        'eliminationOrder': player.eliminationOrder,
      };

  static PlayerModel _playerFromJson(Map<String, dynamic> json) {
    final color = _colorFromJson(json['color']) ?? LudoColor.red;
    final pawns = (json['pawns'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) {
      final pawn = Map<String, dynamic>.from(item);
      return PawnModel(
        id: (pawn['id'] as num?)?.toInt() ?? 0,
        color: _colorFromJson(pawn['color']) ?? color,
        stepCount: (pawn['stepCount'] as num?)?.toInt() ?? -1,
        pairId: pawn['pairId']?.toString(),
        isPairSelected: pawn['isPairSelected'] == true,
      );
    }).toList(growable: false);
    final killCounts = <LudoColor, int>{};
    if (json['killCounts'] is Map) {
      (json['killCounts'] as Map).forEach((key, value) {
        final keyColor = _colorFromJson(key);
        if (keyColor != null && value is num)
          killCounts[keyColor] = value.toInt();
      });
    }
    return PlayerModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Player',
      avatarUrl: json['avatarUrl']?.toString(),
      country: json['country']?.toString() ?? 'World',
      countryFlag: json['countryFlag']?.toString() ?? '🌐',
      coins: (json['coins'] as num?)?.toInt() ?? 0,
      diamonds: (json['diamonds'] as num?)?.toInt() ?? 0,
      color: color,
      isBot: json['isBot'] == true,
      pawns: pawns,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      killCounts: killCounts,
      missedTurns: (json['missedTurns'] as num?)?.toInt() ?? 0,
      isEliminated: json['isEliminated'] == true,
      eliminationOrder: (json['eliminationOrder'] as num?)?.toInt() ?? 0,
    );
  }

  static LudoColor? _colorFromJson(Object? value) {
    for (final color in LudoColor.values) {
      if (color.name == value?.toString()) return color;
    }
    return null;
  }

  GameState copyWith({
    List<PlayerModel>? players,
    String? localPlayerId,
    bool clearLocalPlayerId = false,
    int? currentTurnIndex,
    int? diceValue,
    int? lastRolledDiceValue,
    Map<String, int>? playerDiceValues,
    bool clearDiceValue = false,
    GameTurnPhase? turnPhase,
    int? consecutiveSixes,
    bool? isDiceRolling,
    List<PawnModel>? movablePawns,
    PawnMoveEvent? lastMoveEvent,
    PawnCaptureEvent? lastCaptureEvent,
    bool clearLastCaptureEvent = false,
    bool? isGameOver,
    List<String>? winnerIds,
    String? statusMessage,
    int? rollOpportunityId,
    bool? turnTimerPaused,
    bool? turnTimerDisabled,
    int? turnTimerRemainingMilliseconds,
  }) {
    return GameState(
      players: players ?? this.players,
      localPlayerId:
          clearLocalPlayerId ? null : (localPlayerId ?? this.localPlayerId),
      currentTurnIndex: currentTurnIndex ?? this.currentTurnIndex,
      diceValue: clearDiceValue ? null : (diceValue ?? this.diceValue),
      lastRolledDiceValue: lastRolledDiceValue ?? this.lastRolledDiceValue,
      playerDiceValues: playerDiceValues ?? this.playerDiceValues,
      turnPhase: turnPhase ?? this.turnPhase,
      consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
      isDiceRolling: isDiceRolling ?? this.isDiceRolling,
      movablePawns: movablePawns ?? this.movablePawns,
      lastMoveEvent: lastMoveEvent ?? this.lastMoveEvent,
      lastCaptureEvent: clearLastCaptureEvent
          ? null
          : (lastCaptureEvent ?? this.lastCaptureEvent),
      isGameOver: isGameOver ?? this.isGameOver,
      winnerIds: winnerIds ?? this.winnerIds,
      statusMessage: statusMessage ?? this.statusMessage,
      rollOpportunityId: rollOpportunityId ?? this.rollOpportunityId,
      turnTimerPaused: turnTimerPaused ?? this.turnTimerPaused,
      turnTimerDisabled: turnTimerDisabled ?? this.turnTimerDisabled,
      turnTimerRemainingMilliseconds:
          turnTimerRemainingMilliseconds ?? this.turnTimerRemainingMilliseconds,
    );
  }
}
