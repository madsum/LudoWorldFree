import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/ads/ad_mob_consent_service.dart';
import '../../../core/ads/interstitial_ad_service.dart';
import '../../../core/network/websocket_service.dart';
import '../../../core/network/api_client.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../../shared/widgets/banner_ad_widget.dart';
import '../domain/models/game_state.dart';
import '../domain/models/player_model.dart';
import 'controllers/game_controller.dart';
import 'widgets/exit_game_dialog.dart';
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
  bool _showTimeoutNotice = false;
  Timer? _timeoutNoticeTimer;
  bool _hasTriggeredGameOverAd = false;
  bool _readyToShowVictoryDialog = false;
  StreamSubscription<Map<String, dynamic>>? _onlineSubscription;
  void Function()? _removeOnlineStateListener;
  String? _lastOnlineTurnPlayerId;
  GameNotifier? _onlineGameNotifier;
  final Set<String> _reportedDailyGoalGameIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    if (gameNotifier.isOnlineMode) {
      _onlineGameNotifier = gameNotifier;
      final webSocketService = ref.read(webSocketServiceProvider);
      _onlineSubscription = webSocketService.messageStream.listen((message) {
        if (message['type'] == 'game_state' && message['state'] is Map) {
          gameNotifier.applyRemoteGameState(
            Map<String, dynamic>.from(message['state'] as Map),
          );
        } else if (message['type'] == 'player_disconnected' ||
            message['type'] == 'connection_lost') {
          gameNotifier.pauseTurnTimer();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Your opponent disconnected. Waiting for them to reconnect.'),
          ));
        } else if (message['type'] == 'connection_restored') {
          gameNotifier.resumeTurnTimer();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Connection restored. Syncing the game.'),
            ));
          }
        } else if (message['type'] == 'connection_failed' && mounted) {
          gameNotifier.pauseTurnTimer();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Connection lost. Return to the lobby and search again.'),
          ));
        } else if (message['type'] == 'match_finished' && mounted) {
          ref.read(webSocketServiceProvider).leaveRoom();
          gameNotifier.clearOnlineMatch();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Your opponent left the match.'),
          ));
          Future<void>.delayed(const Duration(seconds: 2), () {
            if (mounted) context.go('/home');
          });
        }
      });
      final initialState = ref.read(gameControllerProvider);
      _lastOnlineTurnPlayerId = initialState.players.isEmpty
          ? null
          : initialState.currentPlayer.id;
      _removeOnlineStateListener = gameNotifier.addListener((next) {
        final previousTurnPlayerId = _lastOnlineTurnPlayerId;
        _lastOnlineTurnPlayerId =
            next.players.isEmpty ? null : next.currentPlayer.id;
        if (gameNotifier.isApplyingRemoteState ||
            !gameNotifier.isOnlineMode ||
            next.players.length != 2) {
          return;
        }
        final localPlayerId = gameNotifier.onlineLocalPlayerId;
        if (previousTurnPlayerId == localPlayerId ||
            next.currentPlayer.id == localPlayerId) {
          webSocketService.sendGameState(next.toJson());
        }
      });
      if (initialState.players.length == 2 &&
          initialState.currentPlayer.id == gameNotifier.onlineLocalPlayerId) {
        webSocketService.sendGameState(initialState.toJson());
      }
    }

    // Preload Fullscreen Interstitial Ad
    Future.microtask(() {
      ref.read(interstitialAdServiceProvider).preloadAd();
    });

    ref.listenManual<GameState>(
      gameControllerProvider,
      (previous, next) {
        if (previous != null) {
          final previousMissedTurns = {
            for (final player in previous.players)
              player.id: player.missedTurns,
          };
          final hasMissedRoll = next.players.any(
            (player) =>
                player.missedTurns > (previousMissedTurns[player.id] ?? 0),
          );
          if (hasMissedRoll) _showTimeoutNoticeOverlay();
        }

        if (next.isGameOver && previous?.isGameOver != true) {
          unawaited(_recordDailyGoalEvents(
            next,
            ref.read(gameControllerProvider.notifier),
          ));
        }

        // Immediately trigger Fullscreen Ad upon Game Over before Victory Dialog
        if (next.isGameOver && !_hasTriggeredGameOverAd) {
          _hasTriggeredGameOverAd = true;
          Future.microtask(() async {
            final interstitialAdService =
                ref.read(interstitialAdServiceProvider);
            await interstitialAdService.showInterstitialAd(
              onAdClosed: () {
                if (mounted) {
                  setState(() {
                    _readyToShowVictoryDialog = true;
                  });
                }
              },
            );
          });
        }
      },
      fireImmediately: true,
    );

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
    _onlineSubscription?.cancel();
    _removeOnlineStateListener?.call();
    final gameNotifier = _onlineGameNotifier;
    _onlineGameNotifier = null;
    if (gameNotifier?.isOnlineMode == true) {
      final playerId = ref.read(authControllerProvider).user?.id;
      ref.read(webSocketServiceProvider).leaveRoom();
      gameNotifier!.clearOnlineMatch();
      if (playerId != null) unawaited(_cancelOnlineMatch(playerId));
    }
    _timeoutNoticeTimer?.cancel();
    ref
        .read(gameControllerProvider.notifier)
        .pauseTurnTimer(updateGameState: false);
    super.dispose();
  }

  Future<void> _cancelOnlineMatch(String playerId) async {
    try {
      await ref.read(apiClientProvider).post(
            '/matchmaking/cancel',
            options: Options(headers: {'X-Player-ID': playerId}),
          );
    } catch (error) {
      debugPrint('Could not clear completed online match: $error');
    }
  }

  Future<void> _recordDailyGoalEvents(
    GameState gameState,
    GameNotifier gameNotifier,
  ) async {
    final user = ref.read(authControllerProvider).user;
    final gameId = gameNotifier.currentGameId;
    if (user == null || gameId.isEmpty || !_reportedDailyGoalGameIds.add(gameId)) {
      return;
    }
    final events = <String>[
      gameNotifier.isOnlineMode ? 'ONLINE_GAME_COMPLETED' : 'GAME_COMPLETED',
    ];
    if (gameState.winnerIds.contains(user.id)) events.add('GAME_WON');
    final dio = ref.read(apiClientProvider);
    for (final eventType in events) {
      try {
        await dio.post(
          '/daily-goals/events',
          data: {
            'eventId': '${gameId}_${user.id}_$eventType',
            'eventType': eventType,
            'gameId': gameId,
          },
          options: Options(headers: {'X-Player-ID': user.id}),
        );
      } catch (error) {
        debugPrint('Daily goal progress could not be saved: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameControllerProvider);
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    final botCount = gameState.players.where((player) => player.isBot).length;
    final isVsComputer =
        botCount == gameState.players.length - 1 && botCount > 0;
    final isTwoPlayerMode = gameState.players.length == 2;
    final isHumanRollWindow = !gameState.isGameOver &&
        gameState.isLocalPlayerTurn &&
        !gameState.isCurrentPlayerBot &&
        gameState.turnPhase == GameTurnPhase.rollDice;
    final humanIndex = gameState.players.indexWhere((player) => !player.isBot);
    final humanColor =
        humanIndex < 0 ? null : gameState.players[humanIndex].color;
    final boardQuarterTurns =
        isVsComputer && humanColor != null
            ? (3 - humanColor.index) % 4
            : gameState.players.isNotEmpty
                ? (3 - gameState.players[0].color.index) % 4
                : 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExitDialog(context);
      },
      child: Scaffold(
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

                  if (!isTwoPlayerMode && !gameState.isGameOver)
                    _buildBackButtonRow(context),

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

                  if (isTwoPlayerMode && !gameState.isGameOver)
                    _buildBackButtonRow(context),

                  // Main Interactive Ludo Board
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final missedTurnIndicators = <Widget>[];
                        for (final player in gameState.players) {
                          final boardCorner =
                              (player.color.index + boardQuarterTurns) % 4;
                          final isLeftSide = boardCorner == 0 || boardCorner == 3;
                          final isTopSide = boardCorner == 0 || boardCorner == 1;
                          final indicatorTop =
                              (constraints.maxHeight * (isTopSide ? 0.25 : 0.75) -
                                      25)
                                  .clamp(0.0, constraints.maxHeight - 50)
                                  .toDouble();

                          missedTurnIndicators.add(
                            Positioned(
                              left: isLeftSide ? 7 : null,
                              right: isLeftSide ? null : 7,
                              top: indicatorTop,
                              child: _BoardMissedTurnIndicator(player: player),
                            ),
                          );
                        }

                        return Stack(
                          children: [
                            Center(
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
                            ...missedTurnIndicators,
                          ],
                        );
                      },
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

              // Victory Dialog (Shows ONLY after the Fullscreen Interstitial Ad completes and is dismissed)
              if (gameState.isGameOver && _readyToShowVictoryDialog)
                Positioned.fill(
                  child: Stack(
                    children: [
                      const ModalBarrier(
                        dismissible: false,
                        color: Color(0x99000000),
                      ),
                      VictoryDialog(
                        gameState: gameState,
                        onPlayAgain: () {
                          setState(() {
                            _hasTriggeredGameOverAd = false;
                            _readyToShowVictoryDialog = false;
                          });
                          gameNotifier.startNewGame(
                            players: gameState.players,
                          );
                        },
                        onExitToLobby: () => context.go('/home'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
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

  Widget _buildBackButtonRow(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
        child: SizedBox(
          height: 32,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _CompactBackButton(
              onPressed: () => _confirmExitDialog(context),
            ),
          ),
        ),
      );

  void _confirmExitDialog(BuildContext context) {
    ExitGameDialog.show(
      context,
      onYes: () {
        final gameNotifier = ref.read(gameControllerProvider.notifier);
        final matchCompleted = gameNotifier.forfeitHumanPlayer();
        if (!matchCompleted) context.go('/home');
      },
      onNo: () {},
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
          width: 32,
          height: 32,
          child: IconButton(
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            splashRadius: 16,
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

class _BoardMissedTurnIndicator extends StatelessWidget {
  const _BoardMissedTurnIndicator({required this.player});

  final PlayerModel player;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${player.name}: ${player.missedTurns} missed turns',
      child: Semantics(
        label: '${player.name}, ${player.missedTurns} missed turns',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xEE05070C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: player.color.color.withValues(alpha: 0.85),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x77000000), blurRadius: 5),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0;
                  index < GameNotifier.maxMissedTurns;
                  index++) ...[
                if (index > 0) const SizedBox(height: 2),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: index < player.missedTurns
                        ? const Color(0xFFFF3B30)
                        : const Color(0xFF20E878),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: index < player.missedTurns
                          ? const Color(0xFFFFB3AE)
                          : const Color(0xFFB9FFD3),
                      width: 0.7,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x8820E878), blurRadius: 3),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
