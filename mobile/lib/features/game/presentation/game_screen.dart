import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/ads/ad_mob_consent_service.dart';
import '../../../shared/widgets/banner_ad_widget.dart';
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

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  bool _completionDialogShown = false;
  bool _showTimeoutNotice = false;
  Timer? _timeoutNoticeTimer;

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
    _timeoutNoticeTimer?.cancel();
    // Cancel the timer without emitting state from a Consumer that is unmounting.
    ref
        .read(gameControllerProvider.notifier)
        .pauseTurnTimer(updateGameState: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameControllerProvider);
    ref.listen(gameControllerProvider, (previous, next) {
      if (previous == null) return;
      final previousMissedTurns = {
        for (final player in previous.players) player.id: player.missedTurns,
      };
      final hasMissedRoll = next.players.any(
        (player) => player.missedTurns > (previousMissedTurns[player.id] ?? 0),
      );
      if (hasMissedRoll) _showTimeoutNoticeOverlay();
    });
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    final botCount = gameState.players.where((player) => player.isBot).length;
    final isVsComputer =
        botCount == gameState.players.length - 1 && botCount > 0;
    final isTwoPlayerMode = gameState.players.length == 2;
    final isHumanRollWindow = !gameState.isGameOver &&
        !gameState.isCurrentPlayerBot &&
        gameState.turnPhase == GameTurnPhase.rollDice;
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
        child: Stack(
          children: [
            Column(
              children: [
                if (!gameState.isGameOver)
                  BannerAdWidget(
                    consentService: ref.read(adMobConsentServiceProvider),
                  ),

                if (!isTwoPlayerMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (gameState.players.isNotEmpty)
                          PlayerInfoCard(
                            player: gameState.players[0],
                            gameState: gameState,
                            isCurrentTurn: gameState.currentTurnIndex == 0,
                            onRoll: () => gameNotifier.rollDice(),
                            compact: true,
                          ),
                        if (gameState.players.length > 1)
                          PlayerInfoCard(
                            player: gameState.players[1],
                            gameState: gameState,
                            isCurrentTurn: gameState.currentTurnIndex == 1,
                            onRoll: () => gameNotifier.rollDice(),
                            compact: true,
                          ),
                      ],
                    ),
                  ),

                // Main Interactive Ludo Board
                Expanded(
                  child: Stack(
                    children: [
                      Center(
                        child: RotatedBox(
                          quarterTurns: boardQuarterTurns,
                          child: LudoBoardWidget(
                            gameState: gameState,
                            onPawnTap: (pawn) => gameNotifier.movePawn(pawn),
                            orientationQuarterTurns: boardQuarterTurns,
                            compactFrame: !isTwoPlayerMode,
                          ),
                        ),
                      ),
                      if (!gameState.isGameOver)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _CompactBackButton(
                            onPressed: () => _confirmExitDialog(context),
                          ),
                        ),
                    ],
                  ),
                ),

                // Bottom Player Info Cards Row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
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
                                showRollArrow: isHumanRollWindow &&
                                    gameState.currentTurnIndex == 0,
                                rollArrowPointsLeft: true,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
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
                                showRollArrow: isHumanRollWindow &&
                                    gameState.currentTurnIndex == 1,
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
                                compact: true,
                                showRollArrow: isHumanRollWindow &&
                                    gameState.currentTurnIndex == 3,
                                rollArrowPointsLeft: true,
                              ),
                            if (gameState.players.length > 2)
                              PlayerInfoCard(
                                player: gameState.players[2],
                                gameState: gameState,
                                isCurrentTurn: gameState.currentTurnIndex == 2,
                                onRoll: () => gameNotifier.rollDice(),
                                compact: true,
                                showRollArrow: isHumanRollWindow &&
                                    gameState.currentTurnIndex == 2,
                              ),
                          ],
                        ),
                ),

                const SizedBox(height: 4),
              ],
            ),
            if (gameState.isGameOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: AppColors.bgDark,
                    child: Column(
                      children: [
                        BannerAdWidget(
                          consentService: ref.read(adMobConsentServiceProvider),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: RotatedBox(
                                quarterTurns: boardQuarterTurns,
                                child: LudoBoardWidget(
                                  gameState: gameState,
                                  onPawnTap: (pawn) =>
                                      gameNotifier.movePawn(pawn),
                                  orientationQuarterTurns: boardQuarterTurns,
                                  compactFrame: !isTwoPlayerMode,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _showTimeoutNotice ? 1 : 0,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xE6000000),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                            width: 1.2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x99000000),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Text(
                          'You ran out of time!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFFFF3B0),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTimeoutNoticeOverlay() {
    if (!mounted) return;
    _timeoutNoticeTimer?.cancel();
    setState(() => _showTimeoutNotice = true);
    _timeoutNoticeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showTimeoutNotice = false);
    });
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
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to exit to the Lobby?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Resume',
              style: GoogleFonts.poppins(color: AppColors.gold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/home');
            },
            child: Text(
              'Exit',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactBackButton extends StatelessWidget {
  const _CompactBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Leave match',
      child: Material(
        color: AppColors.bgNavy.withValues(alpha: 0.92),
        elevation: 4,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.gold, width: 1),
        ),
        child: SizedBox(
          width: 36,
          height: 36,
          child: IconButton(
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            splashRadius: 18,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}
