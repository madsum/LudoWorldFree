import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../domain/models/game_state.dart';
import 'controllers/game_controller.dart';
import 'widgets/ludo_board_widget.dart';
import 'widgets/player_info_card.dart';
import 'widgets/victory_dialog.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  bool _completionDialogShown = false;

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameControllerProvider);
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    final botCount = gameState.players.where((player) => player.isBot).length;
    final isVsComputer =
        botCount == gameState.players.length - 1 && botCount > 0;
    final isTwoPlayerVsComputer = isVsComputer && gameState.players.length == 2;
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

            // Top Player Info Cards Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isTwoPlayerVsComputer)
                    const SizedBox.shrink()
                  else if (gameState.players.isNotEmpty)
                    PlayerInfoCard(
                      player: gameState.players[0],
                      gameState: gameState,
                      showName: false,
                      isCurrentTurn: gameState.currentTurnIndex == 0,
                      onRoll: () => gameNotifier.rollDice(),
                    ),
                  if (isTwoPlayerVsComputer)
                    PlayerInfoCard(
                      player: gameState.players[1],
                      gameState: gameState,
                      showName: false,
                      isCurrentTurn: gameState.currentTurnIndex == 1,
                      onRoll: () => gameNotifier.rollDice(),
                    )
                  else if (gameState.players.length > 1)
                    PlayerInfoCard(
                      player: gameState.players[1],
                      gameState: gameState,
                      showName: false,
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
                  ),
                ),
              ),
            ),

            // Bottom Player Info Cards Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isTwoPlayerVsComputer)
                    PlayerInfoCard(
                      player: gameState.players[0],
                      gameState: gameState,
                      showName: false,
                      isCurrentTurn: gameState.currentTurnIndex == 0,
                      onRoll: () => gameNotifier.rollDice(),
                    )
                  else if (gameState.players.length > 3)
                    PlayerInfoCard(
                      player: gameState.players[3],
                      gameState: gameState,
                      showName: false,
                      isCurrentTurn: gameState.currentTurnIndex == 3,
                      onRoll: () => gameNotifier.rollDice(),
                    ),
                  if (isTwoPlayerVsComputer)
                    const SizedBox.shrink()
                  else if (gameState.players.length > 2)
                    PlayerInfoCard(
                      player: gameState.players[2],
                      gameState: gameState,
                      showName: false,
                      isCurrentTurn: gameState.currentTurnIndex == 2,
                      onRoll: () => gameNotifier.rollDice(),
                    ),
                ],
              ),
            ),

            // Status Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _TurnStatusBanner(
                message: gameState.statusMessage,
                isActive: gameState.turnPhase == GameTurnPhase.rollDice &&
                    !gameState.isGameOver,
                icon: _feedbackIcon(gameState.statusMessage),
                color: _feedbackColor(gameState.statusMessage),
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _feedbackIcon(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('captur')) return Icons.bolt_rounded;
    if (lower.contains('home') ||
        lower.contains('win') ||
        lower.contains('game over')) {
      return Icons.emoji_events_rounded;
    }
    if (lower.contains('six') ||
        lower.contains('bonus') ||
        lower.contains('extra turn')) {
      return Icons.casino_rounded;
    }
    if (lower.contains('forfeit') || lower.contains('three 6')) {
      return Icons.warning_amber_rounded;
    }
    if (lower.contains('rolling')) return Icons.casino_rounded;
    return Icons.info_outline_rounded;
  }

  Color _feedbackColor(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('captur')) return const Color(0xFFFF9F43);
    if (lower.contains('forfeit') || lower.contains('three 6')) {
      return AppColors.red;
    }
    if (lower.contains('home') ||
        lower.contains('win') ||
        lower.contains('game over')) {
      return AppColors.gold;
    }
    return AppColors.gold;
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

class _TurnStatusBanner extends StatefulWidget {
  final String message;
  final bool isActive;
  final IconData icon;
  final Color color;

  const _TurnStatusBanner({
    required this.message,
    required this.isActive,
    required this.icon,
    required this.color,
  });

  @override
  State<_TurnStatusBanner> createState() => _TurnStatusBannerState();
}

class _TurnStatusBannerState extends State<_TurnStatusBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _TurnStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) _syncPulse();
  }

  void _syncPulse() {
    if (widget.isActive) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final amount = _pulse.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: widget.isActive
                ? const Color(0xFF172033)
                    .withValues(alpha: 0.84 + amount * 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: widget.isActive
                ? Border.all(
                    color:
                        AppColors.gold.withValues(alpha: 0.35 + amount * 0.45),
                  )
                : null,
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: AppColors.gold
                          .withValues(alpha: 0.12 + amount * 0.16),
                      blurRadius: 8 + amount * 4,
                    ),
                  ]
                : const [],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Row(
                key: ValueKey(widget.message),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, color: widget.color, size: 17),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.color,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
