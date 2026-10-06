import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import 'controllers/game_controller.dart';
import 'widgets/ludo_board_widget.dart';
import 'widgets/player_info_card.dart';
import 'widgets/victory_dialog.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  bool _completionDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      ref.read(gameControllerProvider.notifier).resumeTurnTimer();
    } else {
      ref.read(gameControllerProvider.notifier).pauseTurnTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    if (lifecycleState == AppLifecycleState.resumed) {
      gameNotifier.resumeTurnTimer();
    } else {
      gameNotifier.pauseTurnTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Cancel the timer without emitting state from a Consumer that is unmounting.
    ref
        .read(gameControllerProvider.notifier)
        .pauseTurnTimer(updateGameState: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameControllerProvider);
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    final botCount = gameState.players.where((player) => player.isBot).length;
    final isVsComputer =
        botCount == gameState.players.length - 1 && botCount > 0;
    final isTwoPlayerMode = gameState.players.length == 2;
    final humanIndex = gameState.players.indexWhere((player) => !player.isBot);
    final humanColor =
        humanIndex < 0 ? null : gameState.players[humanIndex].color;
    final boardQuarterTurns =
        isVsComputer && humanColor != null ? (3 - humanColor.index) % 4 : 0;

    // Automatically trigger victory popup when match finishes
    if (gameState.isGameOver && !_completionDialogShown) {
      _completionDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => VictoryDialog(
            gameState: gameState,
            onPlayAgain: () {
              _completionDialogShown = false;
              Navigator.of(context).pop();
              gameNotifier.startNewGame(players: gameState.players);
            },
            onExitToLobby: () {
              Navigator.of(context).pop();
              context.go('/home');
            },
          ),
        );
      });
    }

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top Match Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.bgNavy,
                border: Border(
                    bottom: BorderSide(color: AppColors.gold, width: 1.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => _confirmExitDialog(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'LUDO MATCH',
                      style: GoogleFonts.cinzel(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.gold),
                    onPressed: () =>
                        gameNotifier.startNewGame(players: gameState.players),
                  ),
                ],
              ),
            ),

            if (!isTwoPlayerMode)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (gameState.players.isNotEmpty)
                      PlayerInfoCard(
                        player: gameState.players[0],
                        gameState: gameState,
                        isCurrentTurn: gameState.currentTurnIndex == 0,
                        onRoll: () => gameNotifier.rollDice(),
                      ),
                    if (gameState.players.length > 1)
                      PlayerInfoCard(
                        player: gameState.players[1],
                        gameState: gameState,
                        isCurrentTurn: gameState.currentTurnIndex == 1,
                        onRoll: () => gameNotifier.rollDice(),
                      ),
                  ],
                ),
              ),

            // Main Interactive Ludo Board
            Expanded(
              child: Center(
                child: RotatedBox(
                  quarterTurns: boardQuarterTurns,
                  child: LudoBoardWidget(
                    gameState: gameState,
                    onPawnTap: (pawn) => gameNotifier.movePawn(pawn),
                    orientationQuarterTurns: boardQuarterTurns,
                  ),
                ),
              ),
            ),

            // Bottom Player Info Cards Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: isTwoPlayerMode
                  ? Row(
                      children: [
                        Expanded(
                          child: PlayerInfoCard(
                            player: gameState.players[0],
                            gameState: gameState,
                            isCurrentTurn: gameState.currentTurnIndex == 0,
                            onRoll: () => gameNotifier.rollDice(),
                            twoPlayerLayout: true,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: SharedDiceButton(
                            gameState: gameState,
                            onRoll: () => gameNotifier.rollDice(),
                          ),
                        ),
                        Expanded(
                          child: PlayerInfoCard(
                            player: gameState.players[1],
                            gameState: gameState,
                            isCurrentTurn: gameState.currentTurnIndex == 1,
                            onRoll: () => gameNotifier.rollDice(),
                            twoPlayerLayout: true,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (gameState.players.length > 3)
                          PlayerInfoCard(
                            player: gameState.players[3],
                            gameState: gameState,
                            isCurrentTurn: gameState.currentTurnIndex == 3,
                            onRoll: () => gameNotifier.rollDice(),
                          ),
                        if (gameState.players.length > 2)
                          PlayerInfoCard(
                            player: gameState.players[2],
                            gameState: gameState,
                            isCurrentTurn: gameState.currentTurnIndex == 2,
                            onRoll: () => gameNotifier.rollDice(),
                          ),
                      ],
                    ),
            ),

            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _confirmExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgNavy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        title: Text(
          'Leave Match?',
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to exit to the Lobby?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Resume',
                style: GoogleFonts.poppins(color: AppColors.gold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/home');
            },
            child:
                Text('Exit', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
