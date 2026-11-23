import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/ad_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/websocket_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/ads/ad_mob_consent_service.dart';
import '../../../core/ads/rewarded_ad_service.dart';
import '../../../core/utils/top_notice.dart';
import '../../../shared/widgets/flying_coin_overlay.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/widgets/guest_setup_dialog.dart';
import '../../game/presentation/controllers/game_controller.dart';
import '../../game/presentation/widgets/exit_game_dialog.dart';
import '../../game/presentation/widgets/mode_config_dialog.dart';
import 'widgets/lobby_bottom_nav.dart';
import 'widgets/lobby_center_graphic.dart';
import 'widgets/lobby_game_card.dart';
import 'widgets/lobby_header_bar.dart';
import 'widgets/online_matchmaking_dialog.dart';
import 'widgets/friend_room_flow_dialog.dart';
import 'widgets/daily_bonus_dialog.dart';
import 'widgets/live_chat_dialog.dart';
import 'widgets/incoming_buddy_request_dialog.dart';
import 'widgets/incoming_voice_call_dialog.dart';
import 'widgets/friend_chat_dialog.dart';
import 'widgets/incoming_buddy_game_dialog.dart';
import 'widgets/buddy_game_match.dart';
import '../../game/presentation/services/voice_call_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.initialFriendRoomCode});

  final String? initialFriendRoomCode;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final ProviderSubscription<AuthState> _authSubscription;
  late final VoiceCallService _voiceCallService;
  Timer? _dailyBonusStartupTimer;
  Timer? _dailyBonusStartupPoll;
  Timer? _buddyRequestPollTimer;
  Timer? _friendInboxPollTimer;
  Timer? _buddyGameInvitePollTimer;
  final ValueNotifier<int> _currentNavIndex = ValueNotifier(0);
  bool _isClaimingReward = false;
  bool _isClaimingDailyBonus = false;
  bool _dailyBonusDialogShowing = false;
  String? _dailyBonusPopupPlayerId;
  String? _buddyRequestPollPlayerId;
  String? _friendInboxPlayerId;
  String? _buddyGameInvitePlayerId;
  DateTime? _outgoingBuddyRequestCursor;
  bool _voiceCallDialogShowing = false;
  bool _buddyRequestPollInFlight = false;
  bool _friendInboxPollInFlight = false;
  bool _buddyGameInvitePollInFlight = false;
  bool _buddyRequestDialogShowing = false;
  bool _friendChatDialogShowing = false;
  bool _buddyGameInviteDialogShowing = false;
  final Set<String> _seenBuddyRequestIds = <String>{};
  final Set<String> _seenFriendMessageIds = <String>{};
  final Set<String> _seenBuddyGameInviteIds = <String>{};
  final List<Map<String, dynamic>> _pendingBuddyRequests = [];
  final Map<String, Map<String, dynamic>> _pendingFriendChats = {};
  final List<Map<String, dynamic>> _pendingBuddyGameInvites = [];
  final GlobalKey _walletKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _waitForStartupUser();
    _voiceCallService = ref.read(voiceCallServiceProvider);
    _voiceCallService.addListener(_handleVoiceCallServiceChanged);
    _authSubscription = ref.listenManual<AuthState>(
      authControllerProvider,
      _handleAuthStateChanged,
      fireImmediately: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = ref.read(authControllerProvider).user?.id;
      if (userId != null) _queueDailyBonusCheck(userId);
      final roomCode = widget.initialFriendRoomCode;
      if (roomCode != null) unawaited(_showFriendRoomFlow(roomCode));
    });
    Future.microtask(() {
      ref.read(rewardedAdServiceProvider).preloadAd();
    });
  }

  void _handleAuthStateChanged(AuthState? previous, AuthState next) {
    final user = next.user;
    if (user == null) {
      _dailyBonusStartupTimer?.cancel();
      _buddyRequestPollTimer?.cancel();
      _friendInboxPollTimer?.cancel();
      _buddyGameInvitePollTimer?.cancel();
      _buddyRequestPollPlayerId = null;
      _friendInboxPlayerId = null;
      _buddyGameInvitePlayerId = null;
      _outgoingBuddyRequestCursor = null;
      _seenBuddyRequestIds.clear();
      _pendingBuddyRequests.clear();
      _seenFriendMessageIds.clear();
      _pendingFriendChats.clear();
      _seenBuddyGameInviteIds.clear();
      _pendingBuddyGameInvites.clear();
      _dailyBonusPopupPlayerId = null;
      unawaited(_voiceCallService.disconnect());
      return;
    }
    unawaited(_voiceCallService.connect(user.id));
    _startBuddyRequestPolling(user.id);
    _startFriendInboxPolling(user.id);
    _startBuddyGameInvitePolling(user.id);
    _dailyBonusStartupPoll?.cancel();
    _dailyBonusStartupPoll = null;
    if (_dailyBonusPopupPlayerId == user.id) return;

    _dailyBonusPopupPlayerId = user.id;
    _queueDailyBonusCheck(user.id);
  }

  void _handleVoiceCallServiceChanged() {
    final currentCall = _voiceCallService.call;
    if (currentCall != null &&
        !_voiceCallDialogShowing &&
        !_voiceCallService.isCallUiMinimized) {
      _voiceCallDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _voiceCallService.call?.callId != currentCall.callId) {
          _voiceCallDialogShowing = false;
          return;
        }
        showDialog<void>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: false,
          builder: (_) => IncomingVoiceCallDialog(
            voiceCallService: _voiceCallService,
            onMinimize: _voiceCallService.minimizeCallUi,
          ),
        ).then((_) {
          _voiceCallDialogShowing = false;
          _showNextIncomingFriendChat();
          _showNextIncomingBuddyGameInvite();
        });
      });
    }
    final error = _voiceCallService.takeLastError();
    if (error != null && mounted) {
      TopNotice.show(context, error);
    }
  }

  void _startBuddyRequestPolling(String playerId) {
    if (_buddyRequestPollPlayerId == playerId) return;
    _buddyRequestPollTimer?.cancel();
    _buddyRequestPollPlayerId = playerId;
    _outgoingBuddyRequestCursor = DateTime.now().toUtc();
    _seenBuddyRequestIds.clear();
    _pendingBuddyRequests.clear();
    unawaited(Future<void>.delayed(
      const Duration(seconds: 1),
      () => _pollIncomingBuddyRequests(playerId),
    ));
    _buddyRequestPollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_pollIncomingBuddyRequests(playerId)),
    );
  }

  void _startFriendInboxPolling(String playerId) {
    if (_friendInboxPlayerId == playerId) return;
    _friendInboxPollTimer?.cancel();
    _friendInboxPlayerId = playerId;
    _seenFriendMessageIds.clear();
    _pendingFriendChats.clear();
    unawaited(Future<void>.delayed(
      const Duration(seconds: 1),
      () => _pollIncomingFriendMessages(playerId),
    ));
    _friendInboxPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_pollIncomingFriendMessages(playerId)),
    );
  }

  Future<void> _pollIncomingFriendMessages(String playerId) async {
    if (_friendInboxPollInFlight ||
        !mounted ||
        ref.read(authControllerProvider).user?.id != playerId) {
      return;
    }
    _friendInboxPollInFlight = true;
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends/inbox',
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final data = response.data;
      if (data is! Map) return;
      final rawMessages = data['messages'];
      if (rawMessages is! List) return;
      for (final raw in rawMessages.whereType<Map>()) {
        final message = Map<String, dynamic>.from(raw);
        final messageId = message['id']?.toString();
        final senderId = message['senderId']?.toString();
        if (messageId == null ||
            senderId == null ||
            !_seenFriendMessageIds.add(messageId)) {
          continue;
        }
        if (_seenFriendMessageIds.length > 2000) {
          _seenFriendMessageIds.clear();
          _seenFriendMessageIds.add(messageId);
        }
        if (FriendChatDialog.openFriendIds.contains(senderId)) continue;
        _pendingFriendChats[senderId] = {
          'friendId': senderId,
          'friendName': message['senderName']?.toString() ?? 'Buddy',
        };
      }
    } catch (_) {
      // Retry on the next inbox poll without interrupting the active screen.
    } finally {
      _friendInboxPollInFlight = false;
    }
    _showNextIncomingFriendChat();
  }

  Future<void> _showNextIncomingFriendChat() async {
    if (!mounted ||
        _friendChatDialogShowing ||
        _buddyRequestDialogShowing ||
        _dailyBonusDialogShowing ||
        _voiceCallService.call != null ||
        _pendingFriendChats.isEmpty) {
      return;
    }
    final entry = _pendingFriendChats.entries.first;
    _pendingFriendChats.remove(entry.key);
    if (FriendChatDialog.openFriendIds.contains(entry.key)) {
      _showNextIncomingFriendChat();
      return;
    }
    _friendChatDialogShowing = true;
    try {
      await FriendChatDialog.show(
        context,
        friendId: entry.value['friendId'] as String,
        friendName: entry.value['friendName'] as String,
      );
    } finally {
      _friendChatDialogShowing = false;
    }
    _showNextIncomingFriendChat();
    _showNextIncomingBuddyGameInvite();
  }

  void _startBuddyGameInvitePolling(String playerId) {
    if (_buddyGameInvitePlayerId == playerId) return;
    _buddyGameInvitePollTimer?.cancel();
    _buddyGameInvitePlayerId = playerId;
    _seenBuddyGameInviteIds.clear();
    _pendingBuddyGameInvites.clear();
    unawaited(Future<void>.delayed(
      const Duration(seconds: 1),
      () => _pollIncomingBuddyGameInvites(playerId),
    ));
    _buddyGameInvitePollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_pollIncomingBuddyGameInvites(playerId)),
    );
  }

  Future<void> _pollIncomingBuddyGameInvites(String playerId) async {
    if (_buddyGameInvitePollInFlight ||
        !mounted ||
        ref.read(authControllerProvider).user?.id != playerId) {
      return;
    }
    _buddyGameInvitePollInFlight = true;
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends/game-invites/incoming',
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final rawEntries = response.data is Map ? response.data['entries'] : null;
      if (rawEntries is List) {
        final activeIds = <String>{};
        for (final raw in rawEntries.whereType<Map>()) {
          final invitation = Map<String, dynamic>.from(raw);
          final invitationId = invitation['id']?.toString();
          if (invitationId == null) continue;
          activeIds.add(invitationId);
          if (_seenBuddyGameInviteIds.add(invitationId)) {
            _pendingBuddyGameInvites.add(invitation);
          }
        }
        _pendingBuddyGameInvites.removeWhere(
          (invitation) => !activeIds.contains(invitation['id']?.toString()),
        );
      }
    } catch (_) {
      // Retry the invitation poll without interrupting the active screen.
    } finally {
      _buddyGameInvitePollInFlight = false;
    }
    _showNextIncomingBuddyGameInvite();
  }

  Future<void> _showNextIncomingBuddyGameInvite() async {
    if (!mounted ||
        _buddyGameInviteDialogShowing ||
        _buddyRequestDialogShowing ||
        _friendChatDialogShowing ||
        _pendingFriendChats.isNotEmpty ||
        _dailyBonusDialogShowing ||
        _voiceCallService.call != null ||
        _pendingBuddyGameInvites.isEmpty) {
      return;
    }
    final invitation = _pendingBuddyGameInvites.removeAt(0);
    _buddyGameInviteDialogShowing = true;
    try {
      final match = await IncomingBuddyGameDialog.show(
        context,
        invitation: invitation,
      );
      if (match != null && mounted) await _startBuddyGame(match);
    } finally {
      _buddyGameInviteDialogShowing = false;
    }
    _showNextIncomingBuddyGameInvite();
  }

  Future<void> _startBuddyGame(BuddyGameMatch match) async {
    final gameController = ref.read(gameControllerProvider.notifier);
    final gameRouteIsOpen =
        GoRouter.of(context).routeInformationProvider.value.uri.path == '/game';
    final webSocketService = ref.read(webSocketServiceProvider);
    final connected = await webSocketService.connectToRoom(
      roomId: match.roomId,
      playerId: match.localPlayerId,
      matchmakingSessionId: match.sessionId,
    );
    if (!mounted) return;
    if (!connected) {
      TopNotice.show(
        context,
        'Could not connect to the buddy game. Please try again.',
      );
      return;
    }
    gameController.configureOnlineMatch(
      roomId: match.roomId,
      playerId: match.localPlayerId,
      selectedColor: match.localColor,
      gameMode: match.gameMode,
      requestDiceRoll: webSocketService.requestDiceRoll,
    );
    gameController.startNewGame(players: match.players);
    if (!gameRouteIsOpen) await context.push('/game');
  }

  Future<void> _pollIncomingBuddyRequests(String playerId) async {
    if (_buddyRequestPollInFlight ||
        !mounted ||
        ref.read(authControllerProvider).user?.id != playerId) {
      return;
    }
    final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
    _buddyRequestPollInFlight = true;
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends/incoming-requests',
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final rawEntries = response.data is Map ? response.data['entries'] : null;
      if (rawEntries is List) {
        final activeRequestIds = <String>{};
        for (final raw in rawEntries.whereType<Map>()) {
          final request = Map<String, dynamic>.from(raw);
          final requestId = request['id']?.toString();
          if (requestId != null) activeRequestIds.add(requestId);
          if (requestId != null && _seenBuddyRequestIds.add(requestId)) {
            _pendingBuddyRequests.add(request);
          }
        }
        _pendingBuddyRequests.removeWhere(
          (request) => !activeRequestIds.contains(request['id']?.toString()),
        );
      }
      final outgoingResponse = await ref.read(apiClientProvider).get(
            '/friends/outgoing-requests',
            queryParameters: {
              'after': (_outgoingBuddyRequestCursor ?? DateTime.now().toUtc())
                  .toIso8601String(),
            },
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final outgoingData = outgoingResponse.data;
      final rawOutgoing = outgoingData is Map ? outgoingData['entries'] : null;
      if (rawOutgoing is List) {
        for (final raw in rawOutgoing.whereType<Map>()) {
          final status = raw['status']?.toString();
          final name = raw['displayName']?.toString() ?? 'Player';
          if (status == 'ACCEPTED') {
            TopNotice.showOnOverlay(
              rootOverlay,
              '$name accepted your buddy request.',
            );
          } else if (status == 'REJECTED') {
            TopNotice.showOnOverlay(
              rootOverlay,
              '$name declined your buddy request.',
            );
          }
        }
      }
      final serverCursor = outgoingData is Map
          ? DateTime.tryParse(outgoingData['cursor']?.toString() ?? '')
          : null;
      _outgoingBuddyRequestCursor = serverCursor ?? DateTime.now().toUtc();
    } catch (_) {
      // Keep the lobby usable during transient API failures; the next poll retries.
    } finally {
      _buddyRequestPollInFlight = false;
    }
    _showNextBuddyRequest();
    _showNextIncomingFriendChat();
    _showNextIncomingBuddyGameInvite();
  }

  Future<void> _showNextBuddyRequest() async {
    if (!mounted ||
        _buddyRequestDialogShowing ||
        _dailyBonusDialogShowing ||
        _pendingBuddyRequests.isEmpty ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final request = _pendingBuddyRequests.removeAt(0);
    _buddyRequestDialogShowing = true;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingBuddyRequestDialog(request: request),
    );
    _buddyRequestDialogShowing = false;
    if (!mounted) return;
    if (accepted == true) {
      final name = request['displayName']?.toString() ?? 'Player';
      TopNotice.show(context, 'You and $name are buddies now.');
    }
    _showNextBuddyRequest();
  }

  void _waitForStartupUser() {
    var attempts = 0;
    _dailyBonusStartupPoll = Timer.periodic(
      const Duration(milliseconds: 250),
      (timer) {
        final authState = ref.read(authControllerProvider);
        if (authState.user != null) {
          timer.cancel();
          _dailyBonusStartupPoll = null;
          _handleAuthStateChanged(null, authState);
          return;
        }
        if (++attempts >= 40) {
          timer.cancel();
          _dailyBonusStartupPoll = null;
        }
      },
    );
  }

  void _queueDailyBonusCheck(String userId) {
    _dailyBonusStartupTimer?.cancel();
    _dailyBonusStartupTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted ||
          _dailyBonusPopupPlayerId != userId ||
          ref.read(authControllerProvider).user?.id != userId) {
        return;
      }
      _loadDailyBonusStatus(userId);
    });
  }

  void _showComingSoonSnackBar(String modeName) {
    if (!mounted) return;
    TopNotice.show(
      context,
      '$modeName mode is coming in the next version!',
      backgroundColor: AppColors.bgNavy,
      foregroundColor: AppColors.gold,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _loadDailyBonusStatus(String userId) async {
    final status =
        await ref.read(authControllerProvider.notifier).getDailyBonusStatus();
    if (!mounted ||
        _dailyBonusPopupPlayerId != userId ||
        ref.read(authControllerProvider).user?.id != userId) {
      return;
    }
    if (status == null) {
      TopNotice.show(
        context,
        'Daily bonus is unavailable. Check your connection and make sure the game backend is running.',
        backgroundColor: AppColors.bgNavy,
        actionLabel: 'RETRY',
        onAction: () => _loadDailyBonusStatus(userId),
      );
      return;
    }
    final bonusStatus = status;
    if (bonusStatus.claimedToday || _dailyBonusDialogShowing) return;

    // The status response arrives after the first Home frame. Showing the
    // dialog directly avoids waiting for another frame, which may not be
    // scheduled while the app is idle on a physical device.
    _dailyBonusDialogShowing = true;
    showDialog<DailyBonusStatus>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => DailyBonusDialog(
        status: bonusStatus,
        onClaim: _watchAdAndClaimDailyBonus,
      ),
    ).then((result) async {
      if (mounted && result?.success == true) {
        final doubleReward = await _showDailyBonusDoubleOffer(result!);
        final wasDoubled =
            doubleReward?.success == true || doubleReward?.doubledToday == true;
        final finalResult = wasDoubled
            ? result.copyWith(
                rewardAmount: result.rewardAmount * 2,
                balance: doubleReward!.balance,
              )
            : result;
        await _flyCoinsFromBottomToWallet();
        await _showDailyBonusCongratulations(finalResult, doubled: wasDoubled);
      } else if (mounted && result?.claimedToday == true) {
        TopNotice.show(
          context,
          'Today’s bonus was already credited. Your wallet has been refreshed.',
          backgroundColor: AppColors.bgNavy,
          foregroundColor: AppColors.gold,
        );
      }
      _dailyBonusDialogShowing = false;
      _showNextBuddyRequest();
      _showNextIncomingFriendChat();
      _showNextIncomingBuddyGameInvite();
    });
  }

  Future<DailyBonusStatus?> _watchAdAndClaimDailyBonus() async {
    if (_isClaimingDailyBonus) return null;
    setState(() => _isClaimingDailyBonus = true);
    final resultCompleter = Completer<DailyBonusStatus?>();
    var earnedReward = false;
    var completed = false;
    void complete(DailyBonusStatus? result) {
      if (completed) return;
      completed = true;
      if (mounted) setState(() => _isClaimingDailyBonus = false);
      resultCompleter.complete(result);
    }

    await ref.read(rewardedAdServiceProvider).showRewardedAd(
      onRewardEarned: (amount, providerRewardId) {
        earnedReward = amount > 0 && providerRewardId.isNotEmpty;
      },
      onAdClosed: () {
        if (!earnedReward) {
          complete(null);
          return;
        }
        ref
            .read(authControllerProvider.notifier)
            .claimDailyBonus()
            .then(complete);
      },
      onError: (error) {
        complete(null);
        if (!mounted) return;
        TopNotice.show(
          context,
          error,
          backgroundColor: AppColors.bgNavy,
          foregroundColor: AppColors.gold,
        );
      },
    );
    return resultCompleter.future;
  }

  Future<DailyBonusStatus?> _showDailyBonusDoubleOffer(
    DailyBonusStatus result,
  ) async {
    final shouldWatch = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B3E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.gold, width: 2),
        ),
        title: Text(
          'DOUBLE YOUR DAILY BONUS?',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: AppColors.gold,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Your ${result.rewardAmount} coin bonus is claimed. Watch one more rewarded ad to earn ${result.rewardAmount} extra coins today.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'NO THANKS',
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.ondemand_video_rounded),
            label: Text(
              'DOUBLE IT',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: const Color(0xFF07122E),
            ),
          ),
        ],
      ),
    );
    if (shouldWatch != true || !mounted) return null;

    final doubleReward = await _watchAdAndDoubleDailyBonus();
    if (doubleReward?.success == true || doubleReward?.doubledToday == true) {
      return doubleReward;
    }
    if (mounted) {
      TopNotice.show(
        context,
        'The extra daily bonus was not credited. Your original bonus is safe.',
        backgroundColor: AppColors.bgNavy,
        foregroundColor: AppColors.gold,
      );
    }
    return null;
  }

  Future<DailyBonusStatus?> _watchAdAndDoubleDailyBonus() async {
    if (_isClaimingDailyBonus) return null;
    setState(() => _isClaimingDailyBonus = true);
    final resultCompleter = Completer<DailyBonusStatus?>();
    String? earnedProviderRewardId;
    var completed = false;
    void complete(DailyBonusStatus? result) {
      if (completed) return;
      completed = true;
      if (mounted) setState(() => _isClaimingDailyBonus = false);
      resultCompleter.complete(result);
    }

    await ref.read(rewardedAdServiceProvider).showRewardedAd(
      onRewardEarned: (amount, providerRewardId) {
        if (amount > 0 && providerRewardId.isNotEmpty) {
          earnedProviderRewardId = providerRewardId;
        }
      },
      onAdClosed: () {
        final rewardId = earnedProviderRewardId;
        if (rewardId == null) {
          complete(null);
          return;
        }
        ref
            .read(authControllerProvider.notifier)
            .doubleDailyBonus(providerRewardId: rewardId)
            .then(complete);
      },
      onError: (error) {
        complete(null);
        if (!mounted) return;
        TopNotice.show(
          context,
          error,
          backgroundColor: AppColors.bgNavy,
          foregroundColor: AppColors.gold,
        );
      },
    );
    return resultCompleter.future;
  }

  Future<void> _showDailyBonusCongratulations(
    DailyBonusStatus result, {
    required bool doubled,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B3E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.gold, width: 2.5),
        ),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFFFEA00),
                    Color(0xFFFF8F00),
                    Color(0xFFB76E00)
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: Color(0xFFFF8F00), blurRadius: 14)
                ],
              ),
              child: const Icon(Icons.monetization_on_rounded,
                  color: Colors.white, size: 52),
            ),
            const SizedBox(height: 16),
            Text('CONGRATULATIONS!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: AppColors.gold,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                )),
            const SizedBox(height: 8),
            Text('You got your Day ${result.rewardDay} daily bonus!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 8),
            if (doubled) ...[
              Text(
                'You watched another ad and doubled today’s reward!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: AppColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text('+${result.rewardAmount} coins added to your wallet',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: AppColors.coinGold,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                )),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: const Color(0xFF07122E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('AWESOME',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  void _launchGameMode(BuildContext context,
      {required bool isVsComputer, required String title}) {
    final user = ref.read(authControllerProvider).user;
    final playerName = user?.name ?? 'Player 1';
    final avatarUrl = user?.avatarUrl;

    ModeConfigDialog.show(
      context,
      title: title,
      isVsComputer: isVsComputer,
      playerName: playerName,
      avatarUrl: avatarUrl,
      country: user?.country ?? 'Local Player',
      countryFlag: user?.countryFlag ?? '🌐',
      coins: user?.coins ?? 0,
      diamonds: user?.diamonds ?? 0,
      onStartGame: (players) {
        final gameController = ref.read(gameControllerProvider.notifier);
        gameController.clearOnlineMatch();
        gameController.startNewGame(players: players);
        context.push('/game');
      },
    );
  }

  Future<void> _showFriendRoomFlow([String? initialRoomCode]) {
    return FriendRoomFlowDialog.show(
      context,
      initialRoomCode: initialRoomCode,
      onStartMatch: (players, roomId, playerId, color, gameMode) {
        final gameController = ref.read(gameControllerProvider.notifier);
        gameController.configureOnlineMatch(
          roomId: roomId,
          playerId: playerId,
          selectedColor: color,
          gameMode: gameMode,
          requestDiceRoll: ref.read(webSocketServiceProvider).requestDiceRoll,
        );
        gameController.startNewGame(players: players);
        context.push('/game');
      },
    );
  }

  void _watchAdAndEarnGold(BuildContext context) async {
    if (_isClaimingReward) return;
    final rewardedAdService = ref.read(rewardedAdServiceProvider);
    var earnedAmount = 0;
    var earnedProviderRewardId = '';

    TopNotice.show(
      context,
      'Loading Rewarded Video Ad...',
      backgroundColor: AppColors.bgNavy,
      duration: const Duration(seconds: 1),
    );

    await rewardedAdService.showRewardedAd(
      onRewardEarned: (amount, rewardId) {
        _isClaimingReward = true;
        earnedAmount = amount;
        earnedProviderRewardId = rewardId;
      },
      onAdClosed: () {
        if (earnedAmount <= 0 || earnedProviderRewardId.isEmpty) {
          _isClaimingReward = false;
          return;
        }
        unawaited(_finishWatchAdReward(
          context,
          earnedAmount,
          earnedProviderRewardId,
        ));
      },
      onError: (error) {
        _isClaimingReward = false;
        if (context.mounted) {
          TopNotice.show(
            context,
            error,
            backgroundColor: AppColors.bgNavy,
            foregroundColor: AppColors.gold,
          );
        }
      },
    );
  }

  Future<void> _finishWatchAdReward(
    BuildContext context,
    int amount,
    String providerRewardId,
  ) async {
    final credited =
        await ref.read(authControllerProvider.notifier).addGoldReward(
              amount: amount,
              providerRewardId: providerRewardId,
            );
    if (!context.mounted) return;
    if (!credited) {
      _isClaimingReward = false;
      TopNotice.show(
        context,
        'Your ad reward could not be added. Please try again.',
        backgroundColor: AppColors.bgNavy,
        foregroundColor: AppColors.gold,
      );
      return;
    }

    await _flyCoinsFromBottomToWallet();
    _isClaimingReward = false;
    if (context.mounted) _showMiddleRewardDialog(context, amount);
  }

  Offset _getWidgetCenter(GlobalKey key, {required Offset fallback}) {
    final renderBox = key.currentContext?.findRenderObject();
    if (renderBox is RenderBox && renderBox.hasSize) {
      return renderBox.localToGlobal(renderBox.size.center(Offset.zero));
    }
    return fallback;
  }

  Future<void> _flyCoinsFromBottomToWallet() {
    if (!mounted) return Future<void>.value();

    final screenSize = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final animationComplete = Completer<void>();
    FlyingCoinOverlay.show(
      context,
      startOffset: Offset(
        screenSize.width / 2,
        screenSize.height - safeBottom - 28,
      ),
      endOffset: _getWidgetCenter(
        _walletKey,
        fallback: Offset(screenSize.width - 60, 32),
      ),
      onComplete: () => animationComplete.complete(),
    );
    return animationComplete.future;
  }

  void _showMiddleRewardDialog(BuildContext context, int amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B3E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.gold, width: 2.5),
        ),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFFFEA00),
                    Color(0xFFFF8F00),
                    Color(0xFFB76E00)
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: Color(0xFFFF8F00), blurRadius: 12),
                ],
              ),
              child: const Icon(
                Icons.monetization_on_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'REWARD EARNED!',
              style: GoogleFonts.cinzel(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.gold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '🎉 You earned +$amount Gold Coins!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '500 Gold Coins have been added to your wallet balance!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side:
                        const BorderSide(color: Color(0xFFB8FF65), width: 1.5),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'AWESOME!',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlagWidget(String flag, {double size = 22}) {
    if (flag == '🌐' ||
        flag == 'assets/images/world.png' ||
        flag.contains('world')) {
      return Image.asset(
        'assets/images/world.png',
        width: size * 1.2,
        height: size * 1.0,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Text('🌐', style: TextStyle(fontSize: size)),
      );
    }
    return Text(flag, style: TextStyle(fontSize: size));
  }

  void _showProfileInfoDialog(BuildContext context) {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    final displayCountry =
        (user.country.contains('assets/images') || user.country.isEmpty)
            ? 'World'
            : user.country;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgNavy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.gold, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.person_pin_rounded, color: AppColors.gold),
            const SizedBox(width: 10),
            Text(
              'PLAYER PROFILE',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildFlagWidget(user.countryFlag, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.name,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Country: $displayCountry',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 2),
            Text(
              'Preferred Mode: ${user.preferredGameType.displayName}',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 2),
            Text(
              'Most Played Mode: ${user.mostPlayedGameType.displayName}',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.gold,
                  fontWeight: FontWeight.bold),
            ),
            if (user.email != null && user.email!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Email: ${user.email}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.white54),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Icon(Icons.monetization_on_rounded,
                        color: AppColors.coinGold, size: 28),
                    const SizedBox(height: 4),
                    Text('${user.coins} Coins',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ],
                ),
                Column(
                  children: [
                    const Icon(Icons.diamond_rounded,
                        color: AppColors.diamondBlue, size: 28),
                    const SizedBox(height: 4),
                    Text('${user.diamonds} Diamonds',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              GuestSetupDialog.showEditProfile(
                context,
                currentName: user.name,
                currentAvatarUrl: user.avatarUrl,
                currentCountry: user.country,
                currentCountryFlag: user.countryFlag,
              );
            },
            child: Text(
              'EDIT PROFILE',
              style: GoogleFonts.poppins(
                  color: AppColors.gold, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final adsConsent = ref.read(adMobConsentServiceProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgNavy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.settings_rounded, color: AppColors.gold),
            const SizedBox(width: 10),
            Text(
              'Settings',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<bool>(
              future: adsConsent.isPrivacyOptionsRequired(),
              builder: (context, snapshot) {
                if (snapshot.data != true) return const SizedBox.shrink();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined,
                      color: AppColors.gold),
                  title: Text(
                    'Privacy choices',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  onTap: adsConsent.showPrivacyOptionsForm,
                );
              },
            ),
            Text(
              '${AppConstants.appName} v${AppConstants.appVersion}',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Developed by ${AppConstants.publisher}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout_rounded, color: AppColors.red),
              title: Text(
                'Sign Out',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: AppColors.red,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authControllerProvider.notifier).signOut();
                if (context.mounted) {
                  context.go('/login');
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(color: AppColors.gold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _dailyBonusStartupTimer?.cancel();
    _dailyBonusStartupPoll?.cancel();
    _buddyRequestPollTimer?.cancel();
    _friendInboxPollTimer?.cancel();
    _buddyGameInvitePollTimer?.cancel();
    _voiceCallService.removeListener(_handleVoiceCallServiceChanged);
    unawaited(_voiceCallService.disconnect());
    _authSubscription.close();
    _currentNavIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final callService = ref.watch(voiceCallServiceProvider);
    final user = authState.user;
    final playerName = user?.name ?? 'Guest Player';
    final avatarUrl = user?.avatarUrl;
    final countryFlag = user?.countryFlag ?? '🌐';
    final diamonds = user?.diamonds ?? 100;
    final coins = user?.coins ?? 2000;

    final mediaQuery = MediaQuery.sizeOf(context);
    final isTablet = mediaQuery.width >= 650;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ExitGameDialog.show(
          context,
          onYes: () {
            SystemNavigator.pop();
          },
          onNo: () {},
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07122E),
        body: Stack(
          children: [
            Column(
              children: [
                LobbyHeaderBar(
                  playerName: playerName,
                  avatarUrl: avatarUrl,
                  countryFlag: countryFlag,
                  diamonds: diamonds,
                  coins: coins,
                  coinWalletKey: _walletKey,
                  level: 3,
                  onProfilePressed: () => _showProfileInfoDialog(context),
                  onSettingsPressed: () => _showSettingsDialog(context),
                  onInboxPressed: () =>
                      _showComingSoonSnackBar('Mailbox Inbox'),
                  onShopPressed: () =>
                      _showComingSoonSnackBar('Coin & Diamond Store'),
                ),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _currentNavIndex,
                    builder: (context, selectedIndex, _) => IndexedStack(
                      index: selectedIndex,
                      children: [
                        SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 6.0),
                        physics: const BouncingScrollPhysics(),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: isTablet ? 600 : double.infinity,
                            ),
                            child: Column(
                          children: [
                            const LobbyCenterGraphic(),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: LobbyGameCard(
                                    title: 'ONLINE',
                                    playerCount: '218,675',
                                    cardType: LobbyCardType.online,
                                    onTap: () {
                                      final user =
                                          ref.read(authControllerProvider).user;
                                      ModeConfigDialog.show(
                                        context,
                                        title: 'Online Multiplayer',
                                        isVsComputer: false,
                                        isOnline: true,
                                        playerName: user?.name ?? 'Player 1',
                                        avatarUrl: user?.avatarUrl,
                                        country: user?.country ?? 'World',
                                        countryFlag: user?.countryFlag ?? '🌐',
                                        coins: user?.coins ?? 0,
                                        diamonds: user?.diamonds ?? 0,
                                        onStartGame: (_) {},
                                        onStartOnlineMatch: (playerCount, color,
                                            entryFee, gameMode) {
                                          OnlineMatchmakingDialog.show(
                                            context,
                                            playerCount: playerCount,
                                            entryFee: entryFee,
                                            selectedColor: color,
                                            gameMode: gameMode,
                                            onMatchFound:
                                                (players, roomId, playerId) {
                                              final gameController = ref.read(
                                                  gameControllerProvider
                                                      .notifier);
                                              gameController
                                                  .configureOnlineMatch(
                                                roomId: roomId,
                                                playerId: playerId,
                                                selectedColor: color,
                                                gameMode: gameMode,
                                                requestDiceRoll: ref
                                                    .read(
                                                        webSocketServiceProvider)
                                                    .requestDiceRoll,
                                              );
                                              gameController.startNewGame(
                                                  players: players);
                                              context.push('/game');
                                            },
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: LobbyGameCard(
                                    title: 'TEAM UP',
                                    playerCount: '4,144',
                                    cardType: LobbyCardType.teamUp,
                                    onTap: () =>
                                        _showComingSoonSnackBar('Team Up 2v2'),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: LobbyGameCard(
                                    title: 'FRIENDS',
                                    playerCount: '16,393',
                                    cardType: LobbyCardType.friends,
                                    onTap: () => _showFriendRoomFlow(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: LobbyGameCard(
                                    title: 'COMPUTER',
                                    cardType: LobbyCardType.computer,
                                    onTap: () => _launchGameMode(context,
                                        isVsComputer: true,
                                        title: 'Vs Computer'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: LobbyGameCard(
                                    title: 'PASS N PLAY',
                                    cardType: LobbyCardType.passNPlay,
                                    onTap: () => _launchGameMode(context,
                                        isVsComputer: false,
                                        title: 'Pass & Play'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () => _watchAdAndEarnGold(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFEA00),
                                      Color(0xFFFF8F00),
                                      Color(0xFFB76E00)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0xFFFF8F00),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: Colors.black38,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.ondemand_video_rounded,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'WATCH AD & EARN GOLD',
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.black87,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          Text(
                                            'Watch a short video to claim free gold!',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: AppColors.gold, width: 1.2),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                              Icons.monetization_on_rounded,
                                              color: AppColors.coinGold,
                                              size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            '+${AdConfig.adRewardGoldAmount}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.gold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                            ),
                          ),
                        ),
                      ),
                        const LiveChatPage(),
                      ],
                    ),
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: _currentNavIndex,
                  builder: (context, selectedIndex, _) => LobbyBottomNav(
                    selectedIndex: selectedIndex,
                    onTap: (index) {
                      if (index != _currentNavIndex.value) {
                        _currentNavIndex.value = index;
                      }
                    },
                  ),
                ),
              ],
            ),
            if (callService.call != null && callService.isCallUiMinimized)
              Positioned(
                right: 12,
                bottom: 86,
                child: MinimizedVoiceCallChip(
                  voiceCallService: callService,
                  onRestore: callService.restoreCallUi,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
