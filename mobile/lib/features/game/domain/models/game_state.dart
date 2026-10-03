import 'pawn_model.dart';
import 'player_model.dart';

enum GameTurnPhase { rollDice, selectPawn, animating, turnEnded }

class GameState {
  final List<PlayerModel> players;
  final int currentTurnIndex;
  final int? diceValue;
  final GameTurnPhase turnPhase;
  final int consecutiveSixes;
  final List<PawnModel> movablePawns;
  final bool isGameOver;
  final List<String> winnerIds;
  final String statusMessage;

  const GameState({
    required this.players,
    this.currentTurnIndex = 0,
    this.diceValue,
    this.turnPhase = GameTurnPhase.rollDice,
    this.consecutiveSixes = 0,
    this.movablePawns = const [],
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
    GameTurnPhase? turnPhase,
    int? consecutiveSixes,
    List<PawnModel>? movablePawns,
    bool? isGameOver,
    List<String>? winnerIds,
    String? statusMessage,
  }) {
    return GameState(
      players: players ?? this.players,
      currentTurnIndex: currentTurnIndex ?? this.currentTurnIndex,
      diceValue: diceValue,
      turnPhase: turnPhase ?? this.turnPhase,
      consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
      movablePawns: movablePawns ?? this.movablePawns,
      isGameOver: isGameOver ?? this.isGameOver,
      winnerIds: winnerIds ?? this.winnerIds,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
