import 'dart:async';

import 'package:dio/dio.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibration/vibration.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/ads/ad_mob_consent_service.dart';
import '../../../core/ads/interstitial_ad_service.dart';
import '../../../core/network/websocket_service.dart';
import '../../../core/network/api_client.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../../shared/widgets/banner_ad_widget.dart';
import '../domain/models/game_state.dart';
import '../domain/models/ludo_color.dart';
import '../domain/models/player_model.dart';
import 'controllers/game_controller.dart';
import 'widgets/exit_game_dialog.dart';
import 'widgets/ludo_board_widget.dart';
import 'widgets/online_chat_panel.dart';
import 'widgets/player_info_card.dart';
import '../../home/presentation/widgets/player_buddy_profile_dialog.dart';
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
  final ValueNotifier<List<OnlineChatMessage>> _chatMessages =
      ValueNotifier<List<OnlineChatMessage>>(<OnlineChatMessage>[]);
  OnlineChatMessage? _latestChatMessage;
  Timer? _chatBubbleTimer;
  Timer? _bellAlertTimer;
  Timer? _opponentDisconnectTimer;
  bool _onlineStateSyncQueued = false;
  final AudioPlayer _bellAudioPlayer = AudioPlayer();
  LudoColor? _bellAlertedPlayerColor;
  bool _rematchPending = false;
  bool _restartingForRematch = false;
  int _rematchAcceptedCount = 0;
  int _rematchPlayerCount = 0;
  final Set<String> _shownRematchDialogs = <String>{};
  final Set<String> _startedRematchRounds = <String>{};
  final Set<String> _disconnectedOnlinePlayerIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    if (gameNotifier.isOnlineMode) {
      _onlineGameNotifier = gameNotifier;
      final webSocketService = ref.read(webSocketServiceProvider);
      _onlineSubscription = webSocketService.messageStream.listen((message) {
        if (message['type'] == 'game_state' &&
            message['state'] is Map &&
            message['playerId'] != gameNotifier.onlineLocalPlayerId) {
          gameNotifier.applyRemoteGameState(
            Map<String, dynamic>.from(message['state'] as Map),
          );
        } else if (message['type'] == 'chat' &&
            message['playerId'] is String &&
            message['text'] is String) {
          final sentAt = message['sentAt'];
          final chat = OnlineChatMessage(
            playerId: message['playerId'] as String,
            text: message['text'] as String,
            sentAt: sentAt is num
                ? DateTime.fromMillisecondsSinceEpoch(sentAt.toInt())
                : DateTime.now(),
          );
          final updated = [..._chatMessages.value, chat];
          if (updated.length > 80) updated.removeRange(0, updated.length - 80);
          _chatMessages.value = updated;
          _latestChatMessage = chat;
          _chatBubbleTimer?.cancel();
          _chatBubbleTimer = Timer(const Duration(seconds: 6), () {
            if (!mounted) return;
            setState(() {
              _latestChatMessage = null;
            });
          });
          if (mounted) setState(() {});
        } else if (message['type'] == 'bell_alert' &&
            message['targetPlayerId'] == gameNotifier.onlineLocalPlayerId) {
          unawaited(_handleBellAlert(message));
        } else if (message['type'] == 'rematch_update') {
          unawaited(_handleRematchUpdate(message));
        } else if (message['type'] == 'error' &&
            message['code'] == 'REMATCH_REJECTED' &&
            mounted) {
          setState(() => _rematchPending = false);
          final reason = message['message']?.toString().trim();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reason == null || reason.isEmpty
                    ? 'The replay request could not be completed.'
                    : reason,
              ),
            ),
          );
        } else if (message['type'] == 'player_disconnected' ||
            message['type'] == 'connection_lost') {
          gameNotifier.pauseTurnTimer();
          final disconnectedPlayerId = _resolveDisconnectedPlayerId(
            message['playerId']?.toString(),
            gameNotifier,
          );
          if (disconnectedPlayerId != null &&
              disconnectedPlayerId != gameNotifier.onlineLocalPlayerId) {
            if (mounted) {
              setState(
                  () => _disconnectedOnlinePlayerIds.add(disconnectedPlayerId));
            }
            _scheduleDisconnectedOpponentForfeit(
              disconnectedPlayerId,
              gameNotifier,
              webSocketService,
            );
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Your opponent disconnected. Waiting briefly for them to reconnect.'),
          ));
        } else if (message['type'] == 'connection_restored') {
          final restoredPlayerId = _resolveDisconnectedPlayerId(
            message['playerId']?.toString(),
            gameNotifier,
          );
          _opponentDisconnectTimer?.cancel();
          if (mounted && restoredPlayerId != null) {
            setState(
                () => _disconnectedOnlinePlayerIds.remove(restoredPlayerId));
          }
          gameNotifier.resumeTurnTimer();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Connection restored. Syncing the game.'),
            ));
          }
        } else if (message['type'] == 'connection_failed' && mounted) {
          gameNotifier.pauseTurnTimer();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Connection lost. Return to the lobby and search again.'),
          ));
        } else if (message['type'] == 'match_finished' && mounted) {
          final leavingPlayerId = message['playerId']?.toString();
          if (message['reason'] == 'opponent_left' &&
              leavingPlayerId != null &&
              leavingPlayerId != gameNotifier.onlineLocalPlayerId) {
            gameNotifier.forfeitDisconnectedOpponent(leavingPlayerId);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Your opponent left. You win by forfeit.'),
            ));
            return;
          }
          unawaited(ref.read(webSocketServiceProvider).leaveRoom());
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
      _lastOnlineTurnPlayerId =
          initialState.players.isEmpty ? null : initialState.currentPlayer.id;
      _removeOnlineStateListener = gameNotifier.addListener((next) {
        final previousTurnPlayerId = _lastOnlineTurnPlayerId;
        _lastOnlineTurnPlayerId =
            next.players.isEmpty ? null : next.currentPlayer.id;
        if (gameNotifier.isApplyingRemoteState ||
            _restartingForRematch ||
            !gameNotifier.isOnlineMode ||
            (next.players.length != 2 && next.players.length != 4)) {
          return;
        }
        final localPlayerId = gameNotifier.onlineLocalPlayerId;
        final localPlayerForfeited = next.isGameOver &&
            next.players.any(
                (player) => player.id == localPlayerId && player.isEliminated);
        if (localPlayerForfeited ||
            previousTurnPlayerId == localPlayerId ||
            next.currentPlayer.id == localPlayerId) {
          if (_onlineStateSyncQueued) return;
          _onlineStateSyncQueued = true;
          // The turn change and next roll-opportunity increment are emitted
          // as consecutive states; sync only after the state settles.
          scheduleMicrotask(() {
            _onlineStateSyncQueued = false;
            if (!mounted || !gameNotifier.isOnlineMode) return;
            webSocketService.sendGameState(
              ref.read(gameControllerProvider).toJson(),
            );
          });
        }
      });
      if ((initialState.players.length == 2 ||
              initialState.players.length == 4) &&
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
          final gameNotifier = ref.read(gameControllerProvider.notifier);
          final localPlayerId = gameNotifier.onlineLocalPlayerId;
          final newlyForfeitedOpponent = next.players.where((player) {
            final wasEliminated = previous.players
                .where((oldPlayer) => oldPlayer.id == player.id)
                .any((oldPlayer) => oldPlayer.isEliminated);
            return gameNotifier.isOnlineMode &&
                !next.isGameOver &&
                player.id != localPlayerId &&
                player.isEliminated &&
                !wasEliminated;
          }).firstOrNull;
          if (newlyForfeitedOpponent != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('${newlyForfeitedOpponent.name} forfeited the game.'),
            ));
          }
        }

        if (next.isGameOver && previous?.isGameOver != true) {
          final gameNotifier = ref.read(gameControllerProvider.notifier);
          if (gameNotifier.isOnlineMode &&
              next.winnerIds.contains(gameNotifier.onlineLocalPlayerId)) {
            unawaited(_refreshWalletAfterWin());
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'You won! Your online match reward is being added to your wallet.'),
            ));
          }
          unawaited(_recordDailyGoalEvents(
            next,
            gameNotifier,
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

  Future<void> _handleRematchUpdate(Map<String, dynamic> message) async {
    if (!mounted) return;
    final status = message['status'] as String?;
    final roundId = message['roundId'] as String?;
    final requesterId = message['requesterId'] as String?;
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    final localPlayerId = gameNotifier.onlineLocalPlayerId;
    if (roundId == null || roundId.isEmpty || requesterId == null) return;
    final acceptedIds = (message['acceptedPlayerIds'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toSet();
    final gameState = ref.read(gameControllerProvider);

    if (status == 'REQUESTED') {
      setState(() {
        _rematchPending = true;
        _rematchAcceptedCount = acceptedIds.length;
        _rematchPlayerCount = gameState.players.length;
      });
      if (requesterId == localPlayerId) {
        return;
      }
      if (!_shownRematchDialogs.add(roundId)) return;
      final requester = gameState.players
              .where((player) => player.id == requesterId)
              .map((player) => player.name)
              .firstOrNull ??
          'Another player';
      final accept = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replay request'),
          content: Text('$requester wants to play another game. Join replay?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      ref.read(webSocketServiceProvider).sendRematchResponse(
            roundId,
            accept == true,
          );
      return;
    }

    if (status == 'DECLINED') {
      setState(() => _rematchPending = false);
      if (requesterId == localPlayerId) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A player declined the replay.'),
        ));
      }
      return;
    }

    if (status == 'ACCEPTED' && _startedRematchRounds.add(roundId)) {
      setState(() {
        _rematchPending = false;
        _hasTriggeredGameOverAd = false;
        _readyToShowVictoryDialog = false;
      });
      _restartingForRematch = true;
      try {
        gameNotifier.startNewGame(players: gameState.players);
      } finally {
        _restartingForRematch = false;
      }
      final freshState = ref.read(gameControllerProvider);
      if (freshState.currentPlayer.id == localPlayerId) {
        ref.read(webSocketServiceProvider).sendGameState(freshState.toJson());
      }
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
    _chatBubbleTimer?.cancel();
    _bellAlertTimer?.cancel();
    _opponentDisconnectTimer?.cancel();
    unawaited(_bellAudioPlayer.dispose());
    _chatMessages.dispose();
    _onlineSubscription?.cancel();
    _removeOnlineStateListener?.call();
    final gameNotifier = _onlineGameNotifier;
    _onlineGameNotifier = null;
    if (gameNotifier?.isOnlineMode == true) {
      final playerId = ref.read(authControllerProvider).user?.id;
      unawaited(ref.read(webSocketServiceProvider).leaveRoom());
      gameNotifier!.clearOnlineMatch();
      if (playerId != null) unawaited(_cancelOnlineMatch(playerId));
    }
    _timeoutNoticeTimer?.cancel();
    ref
        .read(gameControllerProvider.notifier)
        .pauseTurnTimer(updateGameState: false);
    super.dispose();
  }

  Future<void> _handleBellAlert(Map<String, dynamic> message) async {
    final gameState = ref.read(gameControllerProvider);
    final senderId = message['senderPlayerId']?.toString();
    final sender = gameState.players.where((player) => player.id == senderId);
    if (sender.isEmpty || !mounted) return;

    unawaited(_vibrateForBellAlert());
    unawaited(_bellAudioPlayer
        .stop()
        .then((_) => _bellAudioPlayer.play(AssetSource('audio/play-fast.mp3')))
        .catchError((error) {
      debugPrint('Could not play the bell alert: $error');
    }));
    final localPlayer = gameState.players.where(
      (player) =>
          player.id ==
          ref.read(gameControllerProvider.notifier).onlineLocalPlayerId,
    );
    if (localPlayer.isEmpty) return;
    setState(() => _bellAlertedPlayerColor = localPlayer.first.color);
    _bellAlertTimer?.cancel();
    _bellAlertTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _bellAlertedPlayerColor = null);
    });
  }

  Future<void> _vibrateForBellAlert() async {
    try {
      await Vibration.vibrate(pattern: [0, 300, 140, 300, 140, 500]);
    } catch (error) {
      debugPrint('Could not vibrate for the bell alert: $error');
      await HapticFeedback.vibrate();
    }
  }

  void _ringPlayerBell(LudoColor playerColor) {
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    final gameState = ref.read(gameControllerProvider);
    if (!gameNotifier.isOnlineMode || gameState.isGameOver) return;
    final players = gameState.players;
    final target = players.where((player) => player.color == playerColor);
    if (target.isEmpty ||
        target.first.id == gameNotifier.onlineLocalPlayerId ||
        target.first.isEliminated ||
        _disconnectedOnlinePlayerIds.contains(target.first.id)) {
      return;
    }
    ref.read(webSocketServiceProvider).sendBellAlert(target.first.id);
  }

  String? _resolveDisconnectedPlayerId(
    String? messagePlayerId,
    GameNotifier gameNotifier,
  ) {
    if (messagePlayerId != null &&
        messagePlayerId.isNotEmpty &&
        messagePlayerId != 'null') {
      return messagePlayerId;
    }
    if (gameNotifier.currentState.players.length != 2) return null;
    return gameNotifier.currentState.players
        .where((player) => player.id != gameNotifier.onlineLocalPlayerId)
        .map((player) => player.id)
        .firstOrNull;
  }

  void _scheduleDisconnectedOpponentForfeit(
    String disconnectedPlayerId,
    GameNotifier gameNotifier,
    WebSocketService webSocketService,
  ) {
    if (gameNotifier.currentState.players.length != 2) return;
    _opponentDisconnectTimer?.cancel();
    _opponentDisconnectTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted ||
          !_disconnectedOnlinePlayerIds.contains(disconnectedPlayerId)) {
        return;
      }
      if (gameNotifier.forfeitDisconnectedOpponent(disconnectedPlayerId)) {
        webSocketService.forfeitDisconnectedOpponent(disconnectedPlayerId);
      }
    });
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

  VoidCallback? _profileTapFor(PlayerModel player, GameNotifier gameNotifier) {
    if (!gameNotifier.isOnlineMode ||
        player.isBot ||
        player.id == gameNotifier.onlineLocalPlayerId) {
      return null;
    }
    return () => unawaited(PlayerBuddyProfileDialog.show(context, player));
  }

  void _showBoardPlayerProfile(String playerId, GameNotifier gameNotifier) {
    if (!gameNotifier.isOnlineMode ||
        playerId == gameNotifier.onlineLocalPlayerId) {
      return;
    }
    final player = gameNotifier.currentState.players
        .where((candidate) => candidate.id == playerId && !candidate.isBot)
        .firstOrNull;
    if (player != null) {
      unawaited(PlayerBuddyProfileDialog.show(context, player));
    }
  }

  Future<void> _recordDailyGoalEvents(
    GameState gameState,
    GameNotifier gameNotifier,
  ) async {
    final user = ref.read(authControllerProvider).user;
    final gameId = gameNotifier.currentGameId;
    if (user == null ||
        gameId.isEmpty ||
        !_reportedDailyGoalGameIds.add(gameId)) {
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

  Future<void> _refreshWalletAfterWin() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await ref.read(authControllerProvider.notifier).refreshWalletFromBackend();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameControllerProvider);
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    final botCount = gameState.players.where((player) => player.isBot).length;
    final isVsComputer =
        botCount == gameState.players.length - 1 && botCount > 0;
    final isTwoPlayerMode = gameState.players.length == 2;
    final isPlayerRollTurn = !gameState.isGameOver &&
        !gameState.currentPlayer.isBot &&
        !gameState.currentPlayer.isEliminated &&
        gameState.turnPhase == GameTurnPhase.rollDice;
    final humanIndex = gameState.players.indexWhere((player) => !player.isBot);
    final humanColor =
        humanIndex < 0 ? null : gameState.players[humanIndex].color;
    final boardQuarterTurns = isVsComputer && humanColor != null
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
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: gameState.isGameOver ? null : () => gameNotifier.rollDice(),
          child: SafeArea(
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
                                onProfilePressed: _profileTapFor(
                                    gameState.players[0], gameNotifier),
                                isCurrentTurn: gameState.currentTurnIndex == 0,
                                onRoll: () => gameNotifier.rollDice(),
                                compact: true,
                                showRollArrow: isPlayerRollTurn &&
                                    gameState.currentTurnIndex == 0,
                                rollArrowPointsUp: true,
                              ),
                            if (gameState.players.length > 1)
                              PlayerInfoCard(
                                player: gameState.players[1],
                                gameState: gameState,
                                onProfilePressed: _profileTapFor(
                                    gameState.players[1], gameNotifier),
                                isCurrentTurn: gameState.currentTurnIndex == 1,
                                onRoll: () => gameNotifier.rollDice(),
                                compact: true,
                                showRollArrow: isPlayerRollTurn &&
                                    gameState.currentTurnIndex == 1,
                                rollArrowPointsUp: true,
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
                            final isLeftSide =
                                boardCorner == 0 || boardCorner == 3;
                            final isTopSide =
                                boardCorner == 0 || boardCorner == 1;
                            final indicatorTop = (constraints.maxHeight *
                                        (isTopSide ? 0.25 : 0.75) -
                                    25)
                                .clamp(0.0, constraints.maxHeight - 50)
                                .toDouble();

                            missedTurnIndicators.add(
                              Positioned(
                                left: isLeftSide ? 7 : null,
                                right: isLeftSide ? null : 7,
                                top: indicatorTop,
                                child:
                                    _BoardMissedTurnIndicator(player: player),
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
                                    localPlayerId:
                                        gameNotifier.onlineLocalPlayerId,
                                    onBellTap: gameNotifier.isOnlineMode &&
                                            !gameState.isGameOver
                                        ? _ringPlayerBell
                                        : null,
                                    alertedPlayerColor: _bellAlertedPlayerColor,
                                    unavailableBellPlayerIds:
                                        _disconnectedOnlinePlayerIds,
                                    onPlayerProfileTap: gameNotifier
                                            .isOnlineMode
                                        ? (playerId) => _showBoardPlayerProfile(
                                            playerId, gameNotifier)
                                        : null,
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
                                    onProfilePressed: _profileTapFor(
                                        gameState.players[0], gameNotifier),
                                    isCurrentTurn:
                                        gameState.currentTurnIndex == 0,
                                    onRoll: () => gameNotifier.rollDice(),
                                    twoPlayerLayout: true,
                                    showRollArrow: isPlayerRollTurn &&
                                        gameState.currentTurnIndex == 0,
                                    rollArrowPointsUp: false,
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
                                    onProfilePressed: _profileTapFor(
                                        gameState.players[1], gameNotifier),
                                    isCurrentTurn:
                                        gameState.currentTurnIndex == 1,
                                    onRoll: () => gameNotifier.rollDice(),
                                    twoPlayerLayout: true,
                                    showRollArrow: isPlayerRollTurn &&
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
                                    onProfilePressed: _profileTapFor(
                                        gameState.players[3], gameNotifier),
                                    isCurrentTurn:
                                        gameState.currentTurnIndex == 3,
                                    onRoll: () => gameNotifier.rollDice(),
                                    compact: true,
                                    showRollArrow: isPlayerRollTurn &&
                                        gameState.currentTurnIndex == 3,
                                  ),
                                if (gameState.players.length > 2)
                                  PlayerInfoCard(
                                    player: gameState.players[2],
                                    gameState: gameState,
                                    onProfilePressed: _profileTapFor(
                                        gameState.players[2], gameNotifier),
                                    isCurrentTurn:
                                        gameState.currentTurnIndex == 2,
                                    onRoll: () => gameNotifier.rollDice(),
                                    compact: true,
                                    showRollArrow: isPlayerRollTurn &&
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

                if (gameNotifier.isOnlineMode && !gameState.isGameOver)
                  Positioned(
                    left: 8,
                    bottom: 72,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        OnlineChatButton(
                          onPressed: () => _openOnlineChat(context),
                        ),
                        if (_latestChatMessage != null)
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: OnlineChatMessageBubble(
                                text: _latestChatMessage!.text,
                              ),
                            ),
                          ),
                      ],
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
                          replayPending: _rematchPending,
                          replayPendingLabel: _rematchPlayerCount > 0
                              ? 'WAITING ($_rematchAcceptedCount/$_rematchPlayerCount)'
                              : 'WAITING FOR PLAYERS',
                          onPlayAgain: () {
                            if (gameNotifier.isOnlineMode) {
                              if (_rematchPending) return;
                              setState(() {
                                _rematchPending = true;
                                _rematchAcceptedCount = 1;
                                _rematchPlayerCount = gameState.players.length;
                              });
                              final sent = ref
                                  .read(webSocketServiceProvider)
                                  .requestRematch();
                              if (!sent) {
                                setState(() => _rematchPending = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'The game server is disconnected. Reconnect and try again.',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
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

  void _openOnlineChat(BuildContext context) {
    final gameState = ref.read(gameControllerProvider);
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    final playerId = gameNotifier.onlineLocalPlayerId;
    if (playerId == null || !gameNotifier.isOnlineMode) return;
    OnlineChatSheet.show(
      context,
      messages: _chatMessages,
      localPlayerId: playerId,
      playerNames: {
        for (final player in gameState.players) player.id: player.name
      },
      onSend: ref.read(webSocketServiceProvider).sendChatMessage,
    );
  }

  void _confirmExitDialog(BuildContext context) {
    ExitGameDialog.show(
      context,
      onYes: () {
        final gameNotifier = ref.read(gameControllerProvider.notifier);
        if (gameNotifier.isOnlineMode) {
          if (gameNotifier.forfeitHumanPlayer()) return;
          unawaited(_leaveOnlineGame());
          return;
        }
        final matchCompleted = gameNotifier.forfeitHumanPlayer();
        if (!matchCompleted) context.go('/home');
      },
      onNo: () {},
    );
  }

  Future<void> _leaveOnlineGame() async {
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    await ref.read(webSocketServiceProvider).leaveRoom();
    final playerId = ref.read(authControllerProvider).user?.id;
    if (playerId != null) unawaited(_cancelOnlineMatch(playerId));
    gameNotifier.clearOnlineMatch();
    if (mounted) context.go('/home');
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
