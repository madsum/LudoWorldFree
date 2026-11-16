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
import 'services/voice_call_service.dart';
import 'controllers/game_controller.dart';
import 'widgets/exit_game_dialog.dart';
import 'widgets/ludo_board_widget.dart';
import 'widgets/online_chat_panel.dart';
import '../../home/presentation/widgets/incoming_voice_call_dialog.dart';
import '../../home/presentation/widgets/incoming_buddy_request_dialog.dart';
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
  final ValueNotifier<List<OnlineChatMessage>> _chatMessages =
      ValueNotifier<List<OnlineChatMessage>>(<OnlineChatMessage>[]);
  OnlineChatMessage? _latestChatMessage;
  Timer? _chatBubbleTimer;
  Timer? _bellAlertTimer;
  Timer? _opponentDisconnectTimer;
  Timer? _buddyRequestPollTimer;
  bool _buddyRequestPollInFlight = false;
  bool _buddyRequestDialogShowing = false;
  final Set<String> _seenBuddyRequestIds = <String>{};
  final List<Map<String, dynamic>> _pendingBuddyRequests = [];
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
  final Set<String> _existingBuddyOrRequestPlayerIds = <String>{};
  String? _shownIncomingVoiceCallId;
  late final VoiceCallService _voiceCallService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceCallService = ref.read(voiceCallServiceProvider);
    _voiceCallService.addListener(_handleVoiceCallChanged);
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    if (gameNotifier.isOnlineMode) {
      _onlineGameNotifier = gameNotifier;
      final localPlayerId = gameNotifier.onlineLocalPlayerId;
      if (localPlayerId != null) {
        unawaited(_voiceCallService.connect(localPlayerId));
        unawaited(_loadBuddyRelationships(localPlayerId));
      }
      unawaited(Future<void>.delayed(
        const Duration(seconds: 1),
        _pollIncomingBuddyRequests,
      ));
      _buddyRequestPollTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(_pollIncomingBuddyRequests()),
      );
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

  void _handleVoiceCallChanged() {
    final activeCall = _voiceCallService.call;
    if (activeCall?.phase == VoiceCallPhase.incoming &&
        activeCall!.callId != _shownIncomingVoiceCallId) {
      _shownIncomingVoiceCallId = activeCall.callId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _voiceCallService.call?.callId != activeCall.callId ||
            _voiceCallService.call?.phase != VoiceCallPhase.incoming) {
          return;
        }
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => IncomingVoiceCallDialog(
            voiceCallService: _voiceCallService,
          ),
        );
      });
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
    _voiceCallService.removeListener(_handleVoiceCallChanged);
    _buddyRequestPollTimer?.cancel();
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

  Future<void> _loadBuddyRelationships(String playerId) async {
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends',
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final entries = response.data is Map ? response.data['entries'] : null;
      if (!mounted || entries is! List) return;
      setState(() {
        _existingBuddyOrRequestPlayerIds
          ..clear()
          ..addAll(entries
              .whereType<Map>()
              .map(
                (entry) => entry['playerId']?.toString() ?? '',
              )
              .where((id) => id.isNotEmpty));
      });
    } catch (error) {
      debugPrint('Could not load buddy states for this match: $error');
    }
  }

  Future<void> _sendBuddyRequest(String targetPlayerId) async {
    final playerId = _onlineGameNotifier?.onlineLocalPlayerId;
    if (playerId == null ||
        _existingBuddyOrRequestPlayerIds.contains(targetPlayerId)) {
      return;
    }
    try {
      final response = await ref.read(apiClientProvider).post(
            '/friends/requests',
            data: {'playerId': targetPlayerId},
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final status =
          response.data is Map ? response.data['status']?.toString() : null;
      if (!mounted) return;
      setState(() => _existingBuddyOrRequestPlayerIds.add(targetPlayerId));
      final player = _onlineGameNotifier?.currentState.players
          .where((candidate) => candidate.id == targetPlayerId)
          .firstOrNull;
      final name = player?.name ?? 'Player';
      _showVoiceCallMessage(status == 'ACCEPTED'
          ? 'You and $name are buddies now.'
          : 'Buddy request sent to $name.');
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? error.response?.data['message']?.toString()
          : null;
      _showVoiceCallMessage(message ?? 'Could not send the buddy request.');
    }
  }

  Future<void> _pollIncomingBuddyRequests() async {
    final gameNotifier = _onlineGameNotifier;
    final playerId = gameNotifier?.onlineLocalPlayerId;
    if (_buddyRequestPollInFlight ||
        !mounted ||
        gameNotifier == null ||
        playerId == null ||
        !gameNotifier.isOnlineMode) {
      return;
    }
    _buddyRequestPollInFlight = true;
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends/incoming-requests',
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final rawEntries = response.data is Map ? response.data['entries'] : null;
      if (rawEntries is List) {
        final activeIds = <String>{};
        for (final raw in rawEntries.whereType<Map>()) {
          final request = Map<String, dynamic>.from(raw);
          final requestId = request['id']?.toString();
          if (requestId != null) activeIds.add(requestId);
          if (requestId != null && _seenBuddyRequestIds.add(requestId)) {
            _pendingBuddyRequests.add(request);
          }
        }
        _pendingBuddyRequests.removeWhere(
          (request) => !activeIds.contains(request['id']?.toString()),
        );
      }
    } catch (_) {
      // Retry at the next poll without interrupting the online game.
    } finally {
      _buddyRequestPollInFlight = false;
    }
    _showNextIncomingBuddyRequest();
  }

  Future<void> _showNextIncomingBuddyRequest() async {
    final gameNotifier = _onlineGameNotifier;
    if (!mounted ||
        _buddyRequestDialogShowing ||
        _pendingBuddyRequests.isEmpty ||
        gameNotifier == null ||
        gameNotifier.currentState.isGameOver ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final request = _pendingBuddyRequests.removeAt(0);
    _buddyRequestDialogShowing = true;
    gameNotifier.pauseTurnTimer();
    bool? accepted;
    try {
      accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => IncomingBuddyRequestDialog(request: request),
      );
    } finally {
      _buddyRequestDialogShowing = false;
      if (mounted && !gameNotifier.currentState.isGameOver) {
        gameNotifier.resumeTurnTimer();
      }
    }
    if (!mounted) return;
    if (accepted == true) {
      final name = request['displayName']?.toString() ?? 'Player';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You and $name are buddies now.')),
      );
    }
    _showNextIncomingBuddyRequest();
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
    final voiceCallService = ref.watch(voiceCallServiceProvider);
    final voiceCall = voiceCallService.call;
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
                                    existingBuddyOrRequestPlayerIds:
                                        _existingBuddyOrRequestPlayerIds,
                                    onBuddyRequestTap: gameNotifier.isOnlineMode
                                        ? _sendBuddyRequest
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
                                    isCurrentTurn:
                                        gameState.currentTurnIndex == 0,
                                    onRoll: () => gameNotifier.rollDice(),
                                    twoPlayerLayout: true,
                                    onChatPressed: gameNotifier.isOnlineMode
                                        ? () => _openOnlineChat(context)
                                        : null,
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
                                    isCurrentTurn:
                                        gameState.currentTurnIndex == 1,
                                    onRoll: () => gameNotifier.rollDice(),
                                    twoPlayerLayout: true,
                                    onChatPressed: gameNotifier.isOnlineMode
                                        ? () => _openOnlineChat(context)
                                        : null,
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

                if (gameNotifier.isOnlineMode &&
                    !gameState.isGameOver &&
                    (!isTwoPlayerMode || _latestChatMessage != null))
                  Positioned(
                    left: 8,
                    bottom: 72,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (!isTwoPlayerMode)
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

                if (voiceCall != null)
                  Positioned(
                    right: 10,
                    bottom: 78,
                    child: Material(
                      color: const Color(0xF0122447),
                      borderRadius: BorderRadius.circular(24),
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 13, right: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              voiceCall.phase == VoiceCallPhase.connected
                                  ? Icons.call_rounded
                                  : Icons.call_made_rounded,
                              color: voiceCall.phase == VoiceCallPhase.connected
                                  ? Colors.greenAccent
                                  : AppColors.gold,
                              size: 17,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '${voiceCall.phase == VoiceCallPhase.connected ? (voiceCall.muted ? 'MUTED' : 'VOICE') : voiceCall.phase.name.toUpperCase()} ${voiceCall.peerName.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            IconButton(
                              tooltip: voiceCall.muted ? 'Unmute' : 'Mute',
                              onPressed:
                                  voiceCall.phase == VoiceCallPhase.connected
                                      ? voiceCallService.toggleMute
                                      : null,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                voiceCall.muted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            IconButton(
                              tooltip: 'End voice call',
                              onPressed: voiceCallService.endCall,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.call_end_rounded,
                                  color: Colors.redAccent, size: 19),
                            ),
                          ],
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
      onVoiceCallPressed: () =>
          _chooseVoiceCallTarget(gameState.players, gameNotifier),
    );
  }

  Future<void> _chooseVoiceCallTarget(
    List<PlayerModel> players,
    GameNotifier gameNotifier,
  ) async {
    final localPlayerId = gameNotifier.onlineLocalPlayerId;
    if (localPlayerId == null || !gameNotifier.isOnlineMode) return;
    if (ref.read(voiceCallServiceProvider).call != null) {
      _showVoiceCallMessage('Finish your current voice call first.');
      return;
    }
    final opponents = players
        .where((player) => !player.isBot && player.id != localPlayerId)
        .toList(growable: false);
    if (opponents.isEmpty) return;
    PlayerModel? target;
    if (opponents.length == 1) {
      target = opponents.single;
    } else {
      target = await showDialog<PlayerModel>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Call a player'),
          children: [
            for (final player in opponents)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(player),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: player.color.color),
                    const SizedBox(width: 10),
                    Expanded(child: Text(player.name)),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (target == null || !mounted) return;

    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends',
            options: Options(headers: {'X-Player-ID': localPlayerId}),
          );
      final entries = response.data is Map ? response.data['entries'] : null;
      final relationship = entries is List
          ? entries.whereType<Map>().cast<Map>().firstWhere(
                (entry) => entry['playerId']?.toString() == target!.id,
                orElse: () => <String, dynamic>{},
              )
          : <String, dynamic>{};
      if (relationship['status'] != 'ACCEPTED') {
        await _showBuddyOnlyCallDialog(target, relationship);
        return;
      }
    } catch (_) {
      _showVoiceCallMessage('Could not check buddy status. Try again.');
      return;
    }

    try {
      await ref
          .read(voiceCallServiceProvider)
          .startCall(target.id, target.name);
    } catch (error) {
      _showVoiceCallMessage(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _showBuddyOnlyCallDialog(
    PlayerModel target,
    Map relationship,
  ) async {
    final isPending = relationship['status'] == 'PENDING';
    final addBuddy = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Voice calls are for buddies'),
        content: Text(isPending
            ? 'Your buddy request to ${target.name} is still waiting for a reply. You can call after they accept.'
            : 'Add ${target.name} as a buddy first. You can call each other after they accept your request.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CLOSE'),
          ),
          if (!isPending)
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('ADD BUDDY'),
            ),
        ],
      ),
    );
    if (addBuddy != true) return;
    final playerId = _onlineGameNotifier?.onlineLocalPlayerId;
    if (playerId == null) return;
    try {
      await ref.read(apiClientProvider).post(
            '/friends/requests',
            data: {'playerId': target.id},
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      _showVoiceCallMessage('Buddy request sent to ${target.name}.');
    } catch (_) {
      _showVoiceCallMessage('Could not send the buddy request. Try again.');
    }
  }

  void _showVoiceCallMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
