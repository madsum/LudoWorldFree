import 'ludo_color.dart';
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
  final int currentTurnIndex;
  final int? diceValue;
  final GameTurnPhase turnPhase;
  final int consecutiveSixes;
  final bool isDiceRolling;
  final List<PawnModel> movablePawns;
  final PawnMoveEvent? lastMoveEvent;
  final PawnCaptureEvent? lastCaptureEvent;
  final bool isGameOver;
  final List<String> winnerIds;
  final String statusMessage;

  const GameState({
    required this.players,
    this.currentTurnIndex = 0,
    this.diceValue,
    this.turnPhase = GameTurnPhase.rollDice,
    this.consecutiveSixes = 0,
    this.isDiceRolling = false,
    this.movablePawns = const [],
    this.lastMoveEvent,
    this.lastCaptureEvent,
    this.isGameOver = false,
    this.winnerIds = const [],
    this.statusMessage = 'Roll the dice to start!',
  });

  PlayerModel get currentPlayer => players[currentTurnIndex];
  bool get isCurrentPlayerBot => currentPlayer.isBot;

  GameState copyWith({
    List<PlayerModel>? players,
    int? currentTurnIndex,
    int? diceValue,
    bool clearDiceValue = false,
    GameTurnPhase? turnPhase,
    int? consecutiveSixes,
    bool? isDiceRolling,
    List<PawnModel>? movablePawns,
    PawnMoveEvent? lastMoveEvent,
    PawnCaptureEvent? lastCaptureEvent,
    bool? isGameOver,
    List<String>? winnerIds,
    String? statusMessage,
  }) {
    return GameState(
      players: players ?? this.players,
      currentTurnIndex: currentTurnIndex ?? this.currentTurnIndex,
      diceValue: clearDiceValue ? null : (diceValue ?? this.diceValue),
      turnPhase: turnPhase ?? this.turnPhase,
      consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
      isDiceRolling: isDiceRolling ?? this.isDiceRolling,
      movablePawns: movablePawns ?? this.movablePawns,
      lastMoveEvent: lastMoveEvent ?? this.lastMoveEvent,
      lastCaptureEvent: lastCaptureEvent ?? this.lastCaptureEvent,
      isGameOver: isGameOver ?? this.isGameOver,
      winnerIds: winnerIds ?? this.winnerIds,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
