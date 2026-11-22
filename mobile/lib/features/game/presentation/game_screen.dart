import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibration/vibration.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/top_notice.dart';
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
import 'widgets/emoji_picker_dialog.dart';
import 'widgets/ludo_board_widget.dart';
import 'widgets/mjolnir_icon.dart';
import 'widgets/online_chat_panel.dart';
import '../../home/presentation/widgets/incoming_buddy_request_dialog.dart';
import '../../home/presentation/widgets/incoming_voice_call_dialog.dart';
import 'widgets/player_info_card.dart';
import 'widgets/victory_dialog.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
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
  String? _typingPlayerId;
  Timer? _typingIndicatorTimer;
  Timer? _bellAlertTimer;
  Timer? _opponentDisconnectTimer;
  Timer? _buddyRequestPollTimer;
  bool _buddyRequestPollInFlight = false;
  bool _buddyRequestDialogShowing = false;
  bool _stopTimerRequestDialogShowing = false;
  bool _requesterStopTimerDialogShowing = false;
  bool _stopTimerRequestPending = false;
  bool _stopTimerRequestAcknowledged = false;
  String? _pendingStopTimerResultMessage;
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
  final Set<String> _buddyPlayerIds = <String>{};
  final Map<String, String> _outgoingBuddyRequests = <String, String>{};
  final Map<String, GlobalKey> _playerCardKeys = <String, GlobalKey>{};
  final Set<OverlayEntry> _emojiFlights = <OverlayEntry>{};
  late final VoiceCallService _voiceCallService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceCallService = ref.read(voiceCallServiceProvider);
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
        if ((message['type'] == 'game_state' &&
                message['state'] is Map &&
                message['playerId'] != gameNotifier.onlineLocalPlayerId) ||
            (message['type'] == 'game_state_sync' && message['state'] is Map)) {
          final revision = message['revision'];
          gameNotifier.applyRemoteGameState(
            Map<String, dynamic>.from(message['state'] as Map),
            revision: revision is num ? revision.toInt() : null,
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
        } else if (message['type'] == 'emoji_reaction' &&
            message['playerId'] is String &&
            message['emoji'] is String &&
            message['targetPlayerId'] == gameNotifier.onlineLocalPlayerId) {
          final senderId = message['playerId'] as String;
          final localId = gameNotifier.onlineLocalPlayerId;
          if (localId != null && senderId != localId) {
            _playEmojiFlight(senderId, localId, message['emoji'] as String);
          }
        } else if (message['type'] == 'chat_typing' &&
            message['playerId'] is String &&
            message['playerId'] != gameNotifier.onlineLocalPlayerId) {
          final playerId = message['playerId'] as String;
          final isTyping = message['isTyping'] == true;
          _typingIndicatorTimer?.cancel();
          if (isTyping) {
            _typingPlayerId = playerId;
            _typingIndicatorTimer = Timer(const Duration(seconds: 3), () {
              if (!mounted || _typingPlayerId != playerId) return;
              setState(() => _typingPlayerId = null);
            });
          } else if (_typingPlayerId == playerId) {
            _typingPlayerId = null;
          }
          if (mounted) setState(() {});
        } else if (message['type'] == 'dice_timer_stop_request_sent') {
          _showDiceTimerRequestSentDialog();
        } else if (message['type'] == 'dice_timer_stop_requested') {
          unawaited(_showIncomingDiceTimerStopRequest(message, gameNotifier));
        } else if (message['type'] == 'dice_timer_stop_accepted') {
          gameNotifier.disableTurnTimerForFriendlyChat();
          if (mounted) {
            final requesterId = message['requesterPlayerId']?.toString();
            if (requesterId == gameNotifier.onlineLocalPlayerId) {
              _resolveStopTimerRequest(
                'Your dice timer stop request was accepted.',
              );
            } else {
              _showVoiceCallMessage(
                'The dice timer is stopped. The current player can roll when ready.',
              );
            }
          }
        } else if (message['type'] == 'dice_timer_stop_declined' && mounted) {
          final requesterId = message['requesterPlayerId']?.toString();
          if (requesterId == gameNotifier.onlineLocalPlayerId) {
            _resolveStopTimerRequest(
              'Your dice timer stop request was declined.',
            );
          }
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
          TopNotice.show(
            context,
            reason == null || reason.isEmpty
                ? 'The replay request could not be completed.'
                : reason,
          );
        } else if (message['type'] == 'error' &&
            (message['code'] == 'DICE_TIMER_REQUEST_UNAVAILABLE' ||
                message['code'] == 'DICE_TIMER_REQUEST_FAILED' ||
                message['code'] == 'DICE_TIMER_RESPONSE_FAILED') &&
            mounted) {
          _showVoiceCallMessage(message['message']?.toString() ??
              'No other player is connected to receive this request.');
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
          webSocketService.requestCurrentGameState();
        } else if (message['type'] == 'connection_failed' && mounted) {
          gameNotifier.pauseTurnTimer();
        } else if (message['type'] == 'match_finished' && mounted) {
          final finishedRoomId = message['roomId']?.toString();
          if (webSocketService.isRoomSwitchInProgress) return;
          if (finishedRoomId != null &&
              finishedRoomId != webSocketService.roomId) {
            return;
          }
          if (finishedRoomId != null &&
              finishedRoomId != gameNotifier.onlineRoomId) {
            return;
          }
          final leavingPlayerId = message['playerId']?.toString();
          if (message['reason'] == 'opponent_left' &&
              leavingPlayerId != null &&
              leavingPlayerId != gameNotifier.onlineLocalPlayerId) {
            gameNotifier.forfeitDisconnectedOpponent(leavingPlayerId);
            return;
          }
          unawaited(ref.read(webSocketServiceProvider).leaveRoom());
          gameNotifier.clearOnlineMatch();
          Future<void>.delayed(const Duration(seconds: 25), () {
            if (mounted && gameNotifier.onlineRoomId == null) {
              context.go('/home');
            }
          });
        }
      });
      webSocketService.requestCurrentGameState();
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
              gameNotifier.toOnlineWireJson(ref.read(gameControllerProvider)),
            );
          });
        }
      });
      if ((initialState.players.length == 2 ||
              initialState.players.length == 4) &&
          initialState.currentPlayer.id == gameNotifier.onlineLocalPlayerId) {
        webSocketService
            .sendGameState(gameNotifier.toOnlineWireJson(initialState));
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
          if (hasMissedRoll) {
            TopNotice.show(
              context,
              'You ran out of time!',
              foregroundColor: AppColors.gold,
              duration: const Duration(seconds: 2),
            );
          }
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
            TopNotice.show(
              context,
              '${newlyForfeitedOpponent.name} forfeited the game.',
            );
          }
        }

        if (next.isGameOver && previous?.isGameOver != true) {
          final gameNotifier = ref.read(gameControllerProvider.notifier);
          if (gameNotifier.isOnlineMode &&
              next.winnerIds.contains(gameNotifier.onlineLocalPlayerId)) {
            unawaited(_refreshWalletAfterWin());
            TopNotice.show(
              context,
              'You won! Your online match reward is being added to your wallet.',
            );
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
        TopNotice.show(context, 'A player declined the replay.');
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
        ref
            .read(webSocketServiceProvider)
            .sendGameState(gameNotifier.toOnlineWireJson(freshState));
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
    _buddyRequestPollTimer?.cancel();
    _chatBubbleTimer?.cancel();
    _typingIndicatorTimer?.cancel();
    _bellAlertTimer?.cancel();
    _opponentDisconnectTimer?.cancel();
    unawaited(_bellAudioPlayer.dispose());
    _chatMessages.dispose();
    for (final entry in _emojiFlights.toList()) {
      entry.remove();
      entry.dispose();
    }
    _emojiFlights.clear();
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
    ref
        .read(gameControllerProvider.notifier)
        .pauseTurnTimer(updateGameState: false);
    super.dispose();
  }

  Future<void> _handleBellAlert(Map<String, dynamic> message) async {
    final gameState = ref.read(gameControllerProvider);
    final senderId = message['senderPlayerId']?.toString();
    final targetId = message['targetPlayerId']?.toString();
    final localPlayerId =
        ref.read(gameControllerProvider.notifier).onlineLocalPlayerId;
    final sender = gameState.players.where((player) => player.id == senderId);
    final target = gameState.players.where((player) => player.id == targetId);
    if (sender.isEmpty ||
        target.isEmpty ||
        targetId != localPlayerId ||
        !mounted) {
      return;
    }

    unawaited(_vibrateForBellAlert());
    _playBellAlertSound();
    _showBellAlertText(target.first.color);
  }

  void _showBellAlertText(LudoColor playerColor) {
    if (!mounted) return;
    setState(() => _bellAlertedPlayerColor = playerColor);
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

  void _playBellAlertSound() {
    unawaited(_bellAudioPlayer
        .stop()
        .then((_) => _bellAudioPlayer.play(AssetSource('audio/play-fast.mp3')))
        .catchError((error) {
      debugPrint('Could not play the bell alert: $error');
    }));
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
    _playBellAlertSound();
    _showBellAlertText(target.first.color);
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
      final pendingOutgoing = <String, String>{};
      final buddies = <String>{};
      for (final entry in entries.whereType<Map>()) {
        if (entry['status']?.toString() == 'ACCEPTED') {
          final id = entry['playerId']?.toString();
          if (id != null && id.isNotEmpty) buddies.add(id);
        }
        if (entry['direction']?.toString() == 'OUTGOING' &&
            entry['status']?.toString() == 'PENDING') {
          final id = entry['playerId']?.toString();
          if (id != null && id.isNotEmpty) pendingOutgoing[id] = 'PENDING';
        }
      }
      setState(() {
        _existingBuddyOrRequestPlayerIds
          ..clear()
          ..addAll(entries
              .whereType<Map>()
              .map(
                (entry) => entry['playerId']?.toString() ?? '',
              )
              .where((id) => id.isNotEmpty));
        _outgoingBuddyRequests
          ..clear()
          ..addAll(pendingOutgoing);
        _buddyPlayerIds
          ..clear()
          ..addAll(buddies);
      });
    } catch (error) {
      debugPrint('Could not load buddy states for this match: $error');
    }
  }

  Future<void> _sendBuddyRequest(String targetPlayerId) async {
    final playerId = _onlineGameNotifier?.onlineLocalPlayerId;
    if (playerId == null) return;
    if (_existingBuddyOrRequestPlayerIds.contains(targetPlayerId)) {
      _showVoiceCallMessage(_buddyPlayerIds.contains(targetPlayerId)
          ? 'Both of you are already buddy.'
          : 'A buddy request is already pending.');
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
      final alreadyBuddy =
          response.data is Map && response.data['alreadyBuddy'] == true;
      if (!mounted) return;
      setState(() => _existingBuddyOrRequestPlayerIds.add(targetPlayerId));
      if (status != 'ACCEPTED') {
        _outgoingBuddyRequests[targetPlayerId] = 'PENDING';
      } else {
        _buddyPlayerIds.add(targetPlayerId);
      }
      final player = _onlineGameNotifier?.currentState.players
          .where((candidate) => candidate.id == targetPlayerId)
          .firstOrNull;
      final name = player?.name ?? 'Player';
      _showVoiceCallMessage(status == 'ACCEPTED'
          ? alreadyBuddy
              ? 'Both of you are already buddy.'
              : 'You and $name are buddies now.'
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
      await _pollOutgoingBuddyRequests(playerId);
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

  Future<void> _pollOutgoingBuddyRequests(String playerId) async {
    if (_outgoingBuddyRequests.isEmpty) return;
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends',
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final entries = response.data is Map ? response.data['entries'] : null;
      if (!mounted || entries is! List) return;

      final currentOutgoing = <String, String>{};
      for (final entry in entries.whereType<Map>()) {
        if (entry['direction']?.toString() != 'OUTGOING') continue;
        final id = entry['playerId']?.toString();
        final status = entry['status']?.toString();
        if (id != null && id.isNotEmpty && status != null) {
          currentOutgoing[id] = status;
        }
      }

      for (final request in _outgoingBuddyRequests.entries.toList()) {
        if (request.value != 'PENDING') continue;
        final status = currentOutgoing[request.key];
        if (status == 'ACCEPTED') {
          _outgoingBuddyRequests.remove(request.key);
        } else if (status == null) {
          _outgoingBuddyRequests.remove(request.key);
          final player = _onlineGameNotifier?.currentState.players
              .where((candidate) => candidate.id == request.key)
              .firstOrNull;
          _showVoiceCallMessage(
            'Your buddy request to ${player?.name ?? 'Player'} was declined.',
          );
        }
      }
    } catch (error) {
      debugPrint('Could not check outgoing buddy requests: $error');
    }
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
      TopNotice.show(context, 'You and $name are buddies now.');
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
    final isLocalTwoPlayerMode = !gameNotifier.isOnlineMode &&
        isTwoPlayerMode &&
        gameState.players.every((player) => !player.isBot);
    final isPlayerRollTurn = !gameState.isGameOver &&
        !gameState.currentPlayer.isBot &&
        !gameState.currentPlayer.isEliminated &&
        gameState.turnPhase == GameTurnPhase.rollDice;
    final humanIndex = gameState.players.indexWhere((player) => !player.isBot);
    final humanColor =
        humanIndex < 0 ? null : gameState.players[humanIndex].color;
    final localPlayerId = gameNotifier.onlineLocalPlayerId;
    final localOnlinePlayer =
        gameState.players.where((player) => player.id == localPlayerId);
    final perspectiveColor =
        gameNotifier.isOnlineMode && localOnlinePlayer.isNotEmpty
            ? localOnlinePlayer.first.color
            : isVsComputer && humanColor != null
                ? humanColor
                : gameState.players.isNotEmpty
                    ? gameState.players[0].color
                    : null;
    final twoPlayerDisplayOrder = gameNotifier.isOnlineMode &&
            localOnlinePlayer.isNotEmpty
        ? [
            localOnlinePlayer.first,
            ...gameState.players.where((player) => player.id != localPlayerId),
          ]
        : gameState.players;
    final boardQuarterTurns = perspectiveColor != null
        ? (3 - perspectiveColor.index) % 4
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
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.82, -0.72),
                        radius: 1.35,
                        colors: [
                          Color(0xFF183D73),
                          Color(0xFF101B38),
                          AppColors.bgDark,
                        ],
                        stops: [0, 0.48, 1],
                      ),
                    ),
                  ),
                ),
              ),
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
                            _chatAttachedToPlayerCard(
                              playerId: gameState.players[0].id,
                              placeAboveCard: false,
                              onBuddyRequest:
                                  _buddyRequestFor(gameState.players[0].id),
                              card: PlayerInfoCard(
                                player: gameState.players[0],
                                gameState: gameState,
                                isCurrentTurn: gameState.currentTurnIndex == 0,
                                onRoll: () => gameNotifier.rollDice(),
                                compact: true,
                                showRollArrow: isPlayerRollTurn &&
                                    gameState.currentTurnIndex == 0,
                                rollArrowPointsUp: true,
                                onBuddyRequest:
                                    _buddyRequestFor(gameState.players[0].id),
                              ),
                            ),
                          if (gameState.players.length > 1)
                            _chatAttachedToPlayerCard(
                              playerId: gameState.players[1].id,
                              placeAboveCard: false,
                              onBuddyRequest:
                                  _buddyRequestFor(gameState.players[1].id),
                              card: PlayerInfoCard(
                                player: gameState.players[1],
                                gameState: gameState,
                                isCurrentTurn: gameState.currentTurnIndex == 1,
                                onRoll: () => gameNotifier.rollDice(),
                                compact: true,
                                showRollArrow: isPlayerRollTurn &&
                                    gameState.currentTurnIndex == 1,
                                rollArrowPointsUp: true,
                                onBuddyRequest:
                                    _buddyRequestFor(gameState.players[1].id),
                              ),
                            ),
                        ],
                      ),
                    ),

                  if (isTwoPlayerMode && !gameState.isGameOver)
                    _buildBackButtonRow(context),

                  // Main Interactive Ludo Board
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, _) {
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
                                child: _chatAttachedToPlayerCard(
                                  playerId: twoPlayerDisplayOrder[0].id,
                                  placeAboveCard: true,
                                  showChatButton: true,
                                  onBuddyRequest: _buddyRequestFor(
                                      twoPlayerDisplayOrder[0].id),
                                  card: PlayerInfoCard(
                                    player: twoPlayerDisplayOrder[0],
                                    gameState: gameState,
                                    isCurrentTurn: gameState.currentPlayer.id ==
                                        twoPlayerDisplayOrder[0].id,
                                    onRoll: () => gameNotifier.rollDice(),
                                    twoPlayerLayout: true,
                                    showPlayerDot: isLocalTwoPlayerMode,
                                    showRollArrow: isPlayerRollTurn &&
                                        gameState.currentPlayer.id ==
                                            twoPlayerDisplayOrder[0].id,
                                    rollArrowPointsUp: false,
                                    onBuddyRequest: _buddyRequestFor(
                                        twoPlayerDisplayOrder[0].id),
                                  ),
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
                                child: _chatAttachedToPlayerCard(
                                  playerId: twoPlayerDisplayOrder[1].id,
                                  placeAboveCard: true,
                                  onBuddyRequest: _buddyRequestFor(
                                      twoPlayerDisplayOrder[1].id),
                                  card: PlayerInfoCard(
                                    player: twoPlayerDisplayOrder[1],
                                    gameState: gameState,
                                    isCurrentTurn: gameState.currentPlayer.id ==
                                        twoPlayerDisplayOrder[1].id,
                                    onRoll: () => gameNotifier.rollDice(),
                                    twoPlayerLayout: true,
                                    showPlayerDot: isLocalTwoPlayerMode,
                                    showRollArrow: isPlayerRollTurn &&
                                        gameState.currentPlayer.id ==
                                            twoPlayerDisplayOrder[1].id,
                                    onBuddyRequest: _buddyRequestFor(
                                        twoPlayerDisplayOrder[1].id),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (gameState.players.length > 3)
                                _chatAttachedToPlayerCard(
                                  playerId: gameState.players[3].id,
                                  placeAboveCard: true,
                                  showChatButton: true,
                                  onBuddyRequest:
                                      _buddyRequestFor(gameState.players[3].id),
                                  card: PlayerInfoCard(
                                    player: gameState.players[3],
                                    gameState: gameState,
                                    isCurrentTurn:
                                        gameState.currentTurnIndex == 3,
                                    onRoll: () => gameNotifier.rollDice(),
                                    compact: true,
                                    onBuddyRequest: _buddyRequestFor(
                                        gameState.players[3].id),
                                    showRollArrow: isPlayerRollTurn &&
                                        gameState.currentTurnIndex == 3,
                                  ),
                                ),
                              if (gameState.players.length > 2)
                                _chatAttachedToPlayerCard(
                                  playerId: gameState.players[2].id,
                                  placeAboveCard: true,
                                  onBuddyRequest:
                                      _buddyRequestFor(gameState.players[2].id),
                                  card: PlayerInfoCard(
                                    player: gameState.players[2],
                                    gameState: gameState,
                                    isCurrentTurn:
                                        gameState.currentTurnIndex == 2,
                                    onRoll: () => gameNotifier.rollDice(),
                                    compact: true,
                                    onBuddyRequest: _buddyRequestFor(
                                        gameState.players[2].id),
                                    showRollArrow: isPlayerRollTurn &&
                                        gameState.currentTurnIndex == 2,
                                  ),
                                ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 4),
                ],
              ),

              if (voiceCall != null && voiceCallService.isCallUiMinimized)
                Positioned(
                  right: 10,
                  bottom: 78,
                  child: MinimizedVoiceCallChip(
                    voiceCallService: voiceCallService,
                    onRestore: voiceCallService.restoreCallUi,
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
                              TopNotice.show(
                                context,
                                'The game server is disconnected. Reconnect and try again.',
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
    );
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

  Widget _chatAttachedToPlayerCard({
    required Widget card,
    required String playerId,
    required bool placeAboveCard,
    bool showChatButton = false,
    VoidCallback? onBuddyRequest,
  }) {
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    if (!gameNotifier.isOnlineMode || gameNotifier.currentState.isGameOver) {
      return card;
    }

    final controls = Stack(
      clipBehavior: Clip.none,
      children: [
        Align(
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_typingPlayerId == playerId)
                const OnlineChatTypingIndicator(),
            ],
          ),
        ),
        if (_latestChatMessage?.playerId == playerId)
          Positioned(
            right: 0,
            top: placeAboveCard ? null : 38,
            bottom: placeAboveCard ? 38 : null,
            child: IgnorePointer(
              child: OnlineChatMessageBubble(
                text: _latestChatMessage!.text,
              ),
            ),
          ),
      ],
    );

    final playerCard = Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reserve hit-test space for the badge above the card. This keeps
            // the badge outside visually while allowing taps on its full area.
            const SizedBox(height: 39),
            Stack(
              key: _playerCardKeys.putIfAbsent(
                playerId,
                () => GlobalKey(debugLabel: 'player-card-$playerId'),
              ),
              clipBehavior: Clip.none,
              children: [
                if (onBuddyRequest == null)
                  card
                else
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => onBuddyRequest(),
                    child: card,
                  ),
              ],
            ),
          ],
        ),
        if (playerId != gameNotifier.onlineLocalPlayerId)
          Positioned(
            top: 0,
            right: 0,
            child: Material(
              color: const Color(0xFF073D22),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => _openEmojiPicker(playerId),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF35F26B),
                      width: 2.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xAA24EA59),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.emoji_emotions_rounded,
                    color: Color(0xFF49F478),
                    size: 27,
                  ),
                ),
              ),
            ),
          ),
        if (showChatButton && gameNotifier.onlineLocalPlayerId != null)
          Positioned(
            left: 0,
            top: 1,
            child: OnlineChatButton(
              compact: true,
              onPressed: () => _openOnlineChat(context),
            ),
          ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: placeAboveCard
          ? [Align(alignment: Alignment.center, child: controls), playerCard]
          : [playerCard, Align(alignment: Alignment.center, child: controls)],
    );
  }

  VoidCallback? _buddyRequestFor(String playerId) {
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    if (!gameNotifier.isOnlineMode ||
        playerId == gameNotifier.onlineLocalPlayerId ||
        gameNotifier.currentState.players
                .where((player) => player.id == playerId)
                .firstOrNull
                ?.isBot ==
            true) {
      return null;
    }
    return () => unawaited(_sendBuddyRequest(playerId));
  }

  Future<void> _openEmojiPicker(String targetPlayerId) async {
    final emoji = await EmojiPickerDialog.show(context);
    if (emoji == null || !mounted) return;
    final localPlayerId = _onlineGameNotifier?.onlineLocalPlayerId;
    if (localPlayerId == null) return;
    ref.read(webSocketServiceProvider).sendEmojiReaction(
          emoji: emoji,
          targetPlayerId: targetPlayerId,
        );
    _playEmojiFlight(localPlayerId, targetPlayerId, emoji);
  }

  void _playEmojiFlight(String fromPlayerId, String toPlayerId, String emoji) {
    final fromContext = _playerCardKeys[fromPlayerId]?.currentContext;
    final toContext = _playerCardKeys[toPlayerId]?.currentContext;
    if (fromContext == null || toContext == null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final fromBox = fromContext.findRenderObject() as RenderBox?;
    final toBox = toContext.findRenderObject() as RenderBox?;
    if (overlayBox == null || fromBox == null || toBox == null) return;

    final start = fromBox.localToGlobal(
      fromBox.size.center(Offset.zero),
      ancestor: overlayBox,
    );
    final end = toBox.localToGlobal(
      toBox.size.center(Offset.zero),
      ancestor: overlayBox,
    );
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: _EmojiFlightAnimation(
          emoji: emoji,
          start: start,
          end: end,
          onComplete: () {
            if (!_emojiFlights.remove(entry)) return;
            entry.remove();
            entry.dispose();
          },
        ),
      ),
    );
    _emojiFlights.add(entry);
    overlay.insert(entry);
  }

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
      onTypingChanged: ref.read(webSocketServiceProvider).sendChatTyping,
      onVoiceCallPressed: () =>
          _chooseVoiceCallTarget(gameState.players, gameNotifier),
      onVideoCallPressed: () => _chooseVoiceCallTarget(
        gameState.players,
        gameNotifier,
        withVideo: true,
      ),
      onStopTimerPressed: _requestDiceTimerStop,
    );
  }

  void _requestDiceTimerStop() {
    if (_stopTimerRequestPending) {
      _showVoiceCallMessage('Waiting for the other player to respond.');
      return;
    }
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    final localPlayerId = gameNotifier.onlineLocalPlayerId;
    final localPlayer = gameNotifier.currentState.players
        .where((player) => player.id == localPlayerId);
    if (localPlayer.isEmpty) return;
    _stopTimerRequestPending = true;
    _stopTimerRequestAcknowledged = false;
    _pendingStopTimerResultMessage = null;
    final sent = ref
        .read(webSocketServiceProvider)
        .requestDiceTimerStop(localPlayer.first.name);
    if (!sent) {
      _stopTimerRequestPending = false;
      _showVoiceCallMessage(
          'Could not send the dice timer stop request. Reconnecting…');
    } else {
      // Dismiss the chat sheet so the pending request and final SnackBar stay
      // visible above the game board.
      unawaited(Navigator.of(context).maybePop());
    }
  }

  void _showDiceTimerRequestSentDialog() {
    if (!mounted || !_stopTimerRequestPending) return;
    _stopTimerRequestAcknowledged = true;
    final pendingResult = _pendingStopTimerResultMessage;
    if (pendingResult != null) {
      _pendingStopTimerResultMessage = null;
      _stopTimerRequestPending = false;
      _showVoiceCallMessage(pendingResult);
      return;
    }
    if (_requesterStopTimerDialogShowing) return;
    _requesterStopTimerDialogShowing = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request sent'),
        content: const Text(
          'Waiting for the other player to accept or decline your request.',
        ),
      ),
    ).whenComplete(() => _requesterStopTimerDialogShowing = false));
  }

  void _resolveStopTimerRequest(String message) {
    if (!_stopTimerRequestPending) return;
    if (!_requesterStopTimerDialogShowing) {
      if (!_stopTimerRequestAcknowledged) {
        _pendingStopTimerResultMessage = message;
        return;
      }
      _stopTimerRequestPending = false;
      _showVoiceCallMessage(message);
      return;
    }

    _stopTimerRequestPending = false;
    _requesterStopTimerDialogShowing = false;
    unawaited(Navigator.of(context, rootNavigator: true)
        .maybePop()
        .then((_) => _showVoiceCallMessage(message)));
  }

  Future<void> _showIncomingDiceTimerStopRequest(
    Map<String, dynamic> message,
    GameNotifier gameNotifier,
  ) async {
    if (!mounted || _stopTimerRequestDialogShowing) return;
    final requestId = message['requestId']?.toString() ?? '';
    if (requestId.isEmpty) return;
    final requesterId = message['requesterPlayerId']?.toString();
    if (requesterId == gameNotifier.onlineLocalPlayerId) return;
    final expiresAt = (message['expiresAt'] as num?)?.toInt() ?? 0;
    if (expiresAt == 0) return;
    final requesterIndex = gameNotifier.currentState.players
        .indexWhere((player) => player.id == requesterId);
    final playerLabel =
        requesterIndex < 0 ? 'Player' : 'Player ${requesterIndex + 1}';
    final requesterName = message['requesterName']?.toString() ?? 'Player';
    _stopTimerRequestDialogShowing = true;
    bool? accepted;
    try {
      accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Dice timer stop request'),
          content: Text(
            '$playerLabel ($requesterName) requested to stop the dice timer '
            'to start a chat friendly Ludo game.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('DECLINE'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ACCEPT'),
            ),
          ],
        ),
      );
    } finally {
      _stopTimerRequestDialogShowing = false;
    }
    if (!mounted || accepted == null) return;
    ref.read(webSocketServiceProvider).respondToDiceTimerStop(
          requestId: requestId,
          requesterPlayerId: requesterId ?? '',
          expiresAt: expiresAt,
          accept: accepted,
        );
  }

  Future<void> _chooseVoiceCallTarget(
    List<PlayerModel> players,
    GameNotifier gameNotifier,
    {bool withVideo = false},
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
          .startCall(target.id, target.name, withVideo: withVideo);
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
    TopNotice.show(context, message);
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

class _EmojiFlightAnimation extends StatefulWidget {
  const _EmojiFlightAnimation({
    required this.emoji,
    required this.start,
    required this.end,
    required this.onComplete,
  });

  final String emoji;
  final Offset start;
  final Offset end;
  final VoidCallback onComplete;

  @override
  State<_EmojiFlightAnimation> createState() => _EmojiFlightAnimationState();
}

class _EmojiFlightAnimationState extends State<_EmojiFlightAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onComplete();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: SizedBox.expand(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = Curves.easeInOutCubic.transform(_controller.value);
              final control = Offset(
                (widget.start.dx + widget.end.dx) / 2,
                (widget.start.dy + widget.end.dy) / 2 - 72,
              );
              final inverse = 1 - t;
              final point = Offset(
                inverse * inverse * widget.start.dx +
                    2 * inverse * t * control.dx +
                    t * t * widget.end.dx,
                inverse * inverse * widget.start.dy +
                    2 * inverse * t * control.dy +
                    t * t * widget.end.dy,
              );
              final scale = .72 + math.sin(t * math.pi) * .45;
              final opacity = (1.0 -
                  Curves.easeIn.transform(
                    ((t - .84) / .16).clamp(0.0, 1.0).toDouble(),
                  ));
              return Stack(
                children: [
                  Positioned(
                    left: point.dx - 34,
                    top: point.dy - 34,
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.rotate(
                        angle: math.sin(t * math.pi * 2) * .12,
                        child: Transform.scale(
                          scale: scale,
                          child: widget.emoji == 'mjolnir'
                              ? const MjolnirIcon(size: 68)
                              : Text(
                                  widget.emoji,
                                  style: const TextStyle(
                                    fontSize: 56,
                                    shadows: [
                                      Shadow(
                                        color: Color(0xFFFFD54F),
                                        blurRadius: 20,
                                      ),
                                      Shadow(
                                          color: Colors.black87, blurRadius: 8),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
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
