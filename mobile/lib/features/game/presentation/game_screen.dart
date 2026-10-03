import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import 'controllers/game_controller.dart';
import 'widgets/dice_roller_widget.dart';
import 'widgets/ludo_board_widget.dart';
import 'widgets/player_info_card.dart';
import 'widgets/victory_dialog.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameControllerProvider);
    final gameNotifier = ref.read(gameControllerProvider.notifier);

    // Automatically trigger victory popup when match finishes
    if (gameState.isGameOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => VictoryDialog(
            gameState: gameState,
            onPlayAgain: () {
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
                border: Border(bottom: BorderSide(color: AppColors.gold, width: 1.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
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
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.gold),
                    onPressed: () => gameNotifier.startNewGame(players: gameState.players),
                  ),
                ],
              ),
            ),

            // Top Player Info Cards Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (gameState.players.isNotEmpty)
                    PlayerInfoCard(
                      player: gameState.players[0],
                      isCurrentTurn: gameState.currentTurnIndex == 0,
                    ),
                  if (gameState.players.length > 1)
                    PlayerInfoCard(
                      player: gameState.players[1],
                      isCurrentTurn: gameState.currentTurnIndex == 1,
                    ),
                ],
              ),
            ),

            // Main Interactive Ludo Board
            Expanded(
              child: Center(
                child: LudoBoardWidget(
                  gameState: gameState,
                  onPawnTap: (pawn) => gameNotifier.movePawn(pawn),
                ),
              ),
            ),

            // Bottom Player Info Cards Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (gameState.players.length > 3)
                    PlayerInfoCard(
                      player: gameState.players[3],
                      isCurrentTurn: gameState.currentTurnIndex == 3,
                    ),
                  if (gameState.players.length > 2)
                    PlayerInfoCard(
                      player: gameState.players[2],
                      isCurrentTurn: gameState.currentTurnIndex == 2,
                    ),
                ],
              ),
            ),

            // Status Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                gameState.statusMessage,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.gold,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Dice Roller Controls
            DiceRollerWidget(
              gameState: gameState,
              onRoll: () => gameNotifier.rollDice(),
            ),

            const SizedBox(height: 8),
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
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to exit to the Lobby?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Resume', style: GoogleFonts.poppins(color: AppColors.gold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/home');
            },
            child: Text('Exit', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
