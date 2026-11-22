import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/top_notice.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_service.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../game/domain/models/game_mode.dart';
import '../../../game/domain/models/ludo_color.dart';
import '../../../game/domain/models/player_model.dart';

class OnlineMatchmakingDialog extends ConsumerStatefulWidget {
  final int playerCount;
  final int entryFee;
  final LudoColor selectedColor;
  final GameMode gameMode;
  final void Function(
    List<PlayerModel> players,
    String roomId,
    String localPlayerId,
  ) onMatchFound;

  const OnlineMatchmakingDialog({
    super.key,
    required this.playerCount,
    required this.entryFee,
    required this.selectedColor,
    this.gameMode = GameMode.classic,
    required this.onMatchFound,
  });

  static void show(
    BuildContext context, {
    required int playerCount,
    required int entryFee,
    required LudoColor selectedColor,
    GameMode gameMode = GameMode.classic,
    required void Function(
      List<PlayerModel> players,
      String roomId,
      String localPlayerId,
    ) onMatchFound,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => OnlineMatchmakingDialog(
        playerCount: playerCount,
        entryFee: entryFee,
        selectedColor: selectedColor,
        gameMode: gameMode,
        onMatchFound: onMatchFound,
      ),
    );
  }

  @override
  ConsumerState<OnlineMatchmakingDialog> createState() =>
      _OnlineMatchmakingDialogState();
}

class _OnlineMatchmakingDialogState
    extends ConsumerState<OnlineMatchmakingDialog>
    with TickerProviderStateMixin {
  late String _matchmakingSessionId = _createSessionId();
  String? _queuePlayerId;

  late final AnimationController _vsGlowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  Timer? _countdownTimer;
  Timer? _pollingTimer;
  int _secondsRemaining = 60;
  int _selectedEntryFee = 250;

  bool _hasStartedSearch = false;
  bool _isMatchFound = false;
  bool _searchFailed = false;
  bool _offerDialogShowing = false;
  String? _searchFailureMessage;
  bool _isQueueRequestRunning = false;
  String? _queueNotice;
  int _queuePollCount = 0;
  String? _roomId;
  String? _localPlayerId;
  String? _opponentId;
  String? _opponentName;
  String? _opponentAvatar;
  String? _opponentCountry;
  String? _opponentFlag;
  dynamic _matchPlayers;

  String _createSessionId() {
    final random = math.Random.secure();
    return List.generate(
      4,
      (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    ).join();
  }

  @override
  void initState() {
    super.initState();
    _selectedEntryFee = widget.entryFee;
    _hasStartedSearch = true;
    _startCountdown();
    _startMatchmakingQueue();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
        unawaited(_finishSearch());
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  void _beginSearch() {
    if (_hasStartedSearch && !_searchFailed) return;
    _matchmakingSessionId = _createSessionId();
    setState(() {
      _hasStartedSearch = true;
      _searchFailed = false;
      _searchFailureMessage = null;
      _queueNotice = null;
      _secondsRemaining = 60;
      _queuePollCount = 0;
    });
    _startCountdown();
    _startMatchmakingQueue();
  }

  void _startMatchmakingQueue() async {
    final user = ref.read(authControllerProvider).user;
    final playerId = user?.id.trim();
    if (playerId == null || playerId.isEmpty) {
      _pollingTimer?.cancel();
      _countdownTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _hasStartedSearch = false;
        _searchFailed = true;
        _searchFailureMessage = 'Sign in before searching for an online match.';
      });
      return;
    }
    _queuePlayerId = playerId;
    final dio = ref.read(apiClientProvider);
    final joinRequest = {
      'displayName': user?.name ?? 'Player 1',
      'avatarUrl': user?.avatarUrl ?? 'assets/images/black-mask.webp',
      'country': user?.country ?? 'World',
      'countryFlag': user?.countryFlag ?? '🌐',
      'entryFee': _selectedEntryFee,
      'playerCount': widget.playerCount,
      'selectedColor': widget.selectedColor.name,
      'gameMode': widget.gameMode.wireValue,
      'sessionId': _matchmakingSessionId,
    };

    _isQueueRequestRunning = true;
    try {
      final response = await dio.post(
        '/matchmaking/join',
        data: joinRequest,
        options: Options(
          headers: {'X-Player-ID': playerId},
        ),
      );

      if (response.data != null) {
        _handleQueueResponse(response.data);
      }
      if (_isMatchFound || _searchFailed) {
        return;
      }
    } on DioException catch (error) {
      _handleQueueRequestError(error);
      if (_searchFailed) return;
    } catch (_) {
    } finally {
      _isQueueRequestRunning = false;
    }

    if (!mounted || !_hasStartedSearch || _offerDialogShowing) return;

    // Recheck the persisted queue slot so players can join at different times.
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted ||
          _isMatchFound ||
          _searchFailed ||
          _offerDialogShowing ||
          _isQueueRequestRunning) {
        return;
      }
      _isQueueRequestRunning = true;
      _queuePollCount++;
      try {
        final statusResponse = _queuePollCount % 10 == 0
            ? await dio.post(
                '/matchmaking/join',
                data: joinRequest,
                options: Options(headers: {'X-Player-ID': playerId}),
              )
            : await dio.get(
                '/matchmaking/status',
                queryParameters: {
                  'playerCount': widget.playerCount,
                  'sessionId': _matchmakingSessionId,
                },
                options: Options(headers: {'X-Player-ID': playerId}),
              );
        if (statusResponse.data != null) {
          _handleQueueResponse(statusResponse.data);
        }
      } on DioException catch (error) {
        _handleQueueRequestError(error);
      } catch (_) {
      } finally {
        _isQueueRequestRunning = false;
      }
    });
  }

  Future<void> _finishSearch() async {
    _pollingTimer?.cancel();
    if (!mounted ||
        !_hasStartedSearch ||
        _isMatchFound ||
        _offerDialogShowing) {
      return;
    }
    if (_isQueueRequestRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (mounted) unawaited(_finishSearch());
      return;
    }

    _isQueueRequestRunning = true;
    try {
      final user = ref.read(authControllerProvider).user;
      final playerId = _queuePlayerId ?? user?.id.trim();
      if (playerId == null || playerId.isEmpty) {
        _finishWithoutMatch();
        return;
      }
      final response = await ref.read(apiClientProvider).get(
            '/matchmaking/status',
            queryParameters: {
              'playerCount': widget.playerCount,
              'sessionId': _matchmakingSessionId,
            },
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      if (response.data != null) _handleQueueResponse(response.data);
    } catch (_) {
      // Give the same clear timeout result if the final status check fails.
    } finally {
      _isQueueRequestRunning = false;
    }

    if (!mounted || _isMatchFound || _offerDialogShowing || _searchFailed) {
      return;
    }
    _finishWithoutMatch();
  }

  void _finishWithoutMatch() {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    unawaited(_cancelServerQueue());
    if (!mounted) return;
    setState(() {
      _hasStartedSearch = false;
      _searchFailed = true;
      _searchFailureMessage =
          'No player found who is playing with $_selectedEntryFee coins.';
    });
  }

  Future<void> _showLowerStakeOffer(int lowerEntryFee) async {
    if (_offerDialogShowing || !mounted) return;
    _offerDialogShowing = true;
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    final requestedEntryFee = _selectedEntryFee;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF142547),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        title: Text(
          'No $requestedEntryFee-coin match yet',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'A player is available at $lowerEntryFee coins. Would you like to join at that amount?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'NO',
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black87,
            ),
            child: Text(
              'JOIN FOR $lowerEntryFee',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    _offerDialogShowing = false;
    if (!mounted) return;
    if (accepted == true) {
      setState(() {
        _selectedEntryFee = lowerEntryFee;
        _secondsRemaining = 60;
        _searchFailed = false;
        _searchFailureMessage = null;
        _queueNotice = null;
      });
      _startCountdown();
      _startMatchmakingQueue();
      return;
    }

    _finishWithoutMatch();
  }

  bool _isConnectionFailure(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout;

  void _handleQueueRequestError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (_isConnectionFailure(error) ||
        statusCode == null ||
        statusCode >= 500) {
      if (mounted) {
        setState(() => _queueNotice =
            'RECONNECTING TO MATCHMAKING... YOUR PLACE IS SAVED.');
      }
      return;
    }
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    unawaited(_cancelServerQueue());
    if (!mounted) return;
    setState(() {
      _searchFailed = true;
      _searchFailureMessage =
          'MATCHMAKING SERVER ERROR ($statusCode). PLEASE TRY AGAIN.';
    });
  }

  void _handleQueueResponse(dynamic data) {
    if (data is! Map) return;
    if (data['matchFound'] == true) {
      _handleMatchFoundResponse(data);
      return;
    }
    final lowerEntryFee = data['lowerEntryFee'];
    if (lowerEntryFee is num && lowerEntryFee.toInt() < _selectedEntryFee) {
      if (!_offerDialogShowing) {
        unawaited(_showLowerStakeOffer(lowerEntryFee.toInt()));
      }
      return;
    }
    final message = data['message']?.toString().trim();
    if (message == null ||
        message.isEmpty ||
        message == 'Searching for online players...') {
      if (_queueNotice != null && mounted) {
        setState(() => _queueNotice = null);
      }
      return;
    }

    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    unawaited(_cancelServerQueue());
    if (!mounted) return;
    setState(() {
      _searchFailed = true;
      _searchFailureMessage = message;
    });
  }

  void _handleMatchFoundResponse(dynamic data) {
    if (_isMatchFound) return;
    final matchedPlayerCount = (data['playerCount'] as num?)?.toInt();
    if (matchedPlayerCount != widget.playerCount) {
      _failMatchedRoom(
          'The room did not match your selected player count. Please search again.');
      return;
    }
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _isMatchFound = true;
      _roomId = data['roomId']?.toString();
      _localPlayerId = data['playerId']?.toString();
      _opponentId = data['opponentId']?.toString();
      _opponentName = data['opponentName'] ?? 'Opponent';
      _opponentAvatar =
          data['opponentAvatarUrl'] ?? 'assets/images/blue-mask.webp';
      _opponentCountry = data['opponentCountry'] ?? 'World';
      _opponentFlag = data['opponentCountryFlag'] ?? '🌐';
      _matchPlayers = data['players'];
    });

    _launchGameWithOpponent();
  }

  Future<void> _launchGameWithOpponent() async {
    final user = ref.read(authControllerProvider).user;
    final roomId = _roomId;
    final localPlayerId = _localPlayerId ??
        (user == null ? null : _resolveBackendPlayerId(user.id));
    final opponentId = _opponentId;
    if (user == null ||
        user.id.isEmpty ||
        roomId == null ||
        localPlayerId == null ||
        opponentId == null) {
      _failMatchedRoom(
          'The match details were incomplete. Please search again.');
      return;
    }
    final connected = await ref.read(webSocketServiceProvider).connectToRoom(
          roomId: roomId,
          playerId: localPlayerId,
          matchmakingSessionId: _matchmakingSessionId,
        );
    if (!connected || !mounted) {
      _failMatchedRoom(
          'Could not connect both players to the game room. No game was started.');
      return;
    }

    final roomPlayers = _playersFromResponse(_matchPlayers, user);
    if (roomPlayers == null) {
      _failMatchedRoom(widget.playerCount == 4
          ? 'This room does not have four human players yet. Please search again.'
          : 'The match details were incomplete. Please search again.');
      return;
    }

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || _roomId == null) return;
      Navigator.of(context).pop();
      widget.onMatchFound(roomPlayers, roomId, localPlayerId);
    });
  }

  List<PlayerModel>? _playersFromResponse(dynamic response, dynamic user) {
    final rawPlayers = response is List ? response : null;
    if (rawPlayers != null) {
      final players = <PlayerModel>[];
      for (final raw in rawPlayers) {
        if (raw is! Map) return null;
        final id = raw['id']?.toString();
        final name = raw['name']?.toString();
        final colorName = raw['color']?.toString();
        final color =
            LudoColor.values.where((value) => value.name == colorName);
        if (id == null || name == null || color.isEmpty) return null;
        players.add(PlayerModel.initial(
          id: id,
          name: name,
          avatarUrl: raw['avatarUrl']?.toString(),
          country: raw['country']?.toString() ?? 'World',
          countryFlag: raw['countryFlag']?.toString() ?? '🌐',
          coins: (raw['coins'] as num?)?.toInt() ?? 0,
          diamonds: (raw['diamonds'] as num?)?.toInt() ?? 0,
          color: color.first,
          isBot: false,
        ));
      }
      if (players.length != widget.playerCount ||
          players.any((player) => player.isBot)) {
        return null;
      }
      return players;
    }

    // Compatibility with the existing two-player matchmaking response.
    if (widget.playerCount != 2 || _opponentId == null) return null;
    final human = PlayerModel.initial(
      id: _localPlayerId ?? _resolveBackendPlayerId(user.id),
      name: user.name,
      avatarUrl: user.avatarUrl ?? 'assets/images/black-mask.webp',
      country: user.country,
      countryFlag: user.countryFlag,
      coins: user.coins,
      diamonds: user.diamonds,
      color: widget.selectedColor,
      isBot: false,
    );
    final opponentColor = LudoColor
        .values[(widget.selectedColor.index + 2) % LudoColor.values.length];
    final opponent = PlayerModel.initial(
      id: _opponentId!,
      name: _opponentName ?? 'Opponent',
      avatarUrl: _opponentAvatar ?? 'assets/images/blue-mask.webp',
      country: _opponentCountry ?? 'World',
      countryFlag: _opponentFlag ?? '🌐',
      color: opponentColor,
      isBot: false,
    );
    return [human, opponent];
  }

  String _resolveBackendPlayerId(String playerId) {
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (uuidPattern.hasMatch(playerId)) return playerId.toLowerCase();

    // Java PlayerIdResolver uses nameUUIDFromBytes for non-UUID user IDs.
    final bytes = md5.convert(utf8.encode(playerId)).bytes;
    bytes[6] = (bytes[6] & 0x0f) | 0x30;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  void _failMatchedRoom(String message) {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    unawaited(ref.read(webSocketServiceProvider).leaveRoom());
    _cancelServerQueue();
    if (!mounted) return;
    setState(() {
      _isMatchFound = false;
      _searchFailed = true;
      _searchFailureMessage = message;
    });
    TopNotice.show(context, message);
  }

  Future<void> _cancelServerQueue() async {
    try {
      final dio = ref.read(apiClientProvider);
      final user = ref.read(authControllerProvider).user;
      final playerId = _queuePlayerId ?? user?.id.trim();
      if (playerId == null || playerId.isEmpty) return;
      await dio.post(
        '/matchmaking/cancel',
        queryParameters: {'sessionId': _matchmakingSessionId},
        options: Options(headers: {'X-Player-ID': playerId}),
      );
    } catch (_) {}
  }

  void _cancelMatchmaking() async {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    await ref.read(webSocketServiceProvider).leaveRoom();
    await _cancelServerQueue();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _vsGlowController.dispose();
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final myName = user?.name ?? 'madsum1984';
    final myAvatar = user?.avatarUrl ?? 'assets/images/black-mask.webp';

    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: const Color(0xEB8B0000), // Dark Red Ludo King Background
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ludo World Free 3D Logo Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            color: AppColors.gold,
                            size: 32,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'LUDO WORLD FREE',
                            style: GoogleFonts.cinzel(
                              color: AppColors.gold,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              shadows: const [
                                Shadow(
                                    color: Colors.black,
                                    blurRadius: 8,
                                    offset: Offset(0, 3)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ONLINE MULTIPLAYER Title Banner
                      Text(
                        'ONLINE MULTIPLAYER',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFFFFEA00),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          shadows: const [
                            Shadow(
                                color: Colors.black,
                                blurRadius: 6,
                                offset: Offset(0, 2)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Mode & Entry Fee Banner Box
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7A0000),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24, width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Game Mode',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.emoji_events_rounded,
                                        color: AppColors.gold, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Classic',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                                width: 1, height: 28, color: Colors.white24),
                            Column(
                              children: [
                                Text(
                                  'Entry Amount',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.monetization_on_rounded,
                                        color: AppColors.coinGold, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$_selectedEntryFee',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (_searchFailed) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _beginSearch,
                            icon: const Icon(Icons.search_rounded),
                            label: Text(
                              'SEARCH AGAIN',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD700),
                              foregroundColor: const Color(0xFF3D0909),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Show one slot per human seat while matchmaking.
                      if (widget.playerCount == 4)
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _PlayerCardBox(
                              name: myName,
                              avatarUrl: myAvatar,
                              borderColor: const Color(0xFFE53935),
                              size: 76,
                            ),
                            for (var seat = 2; seat <= 4; seat++)
                              _PlayerCardBox(
                                name: 'Player $seat',
                                borderColor: const Color(0xFF1E88E5),
                                isSearching: _hasStartedSearch &&
                                    !_isMatchFound &&
                                    !_searchFailed,
                                size: 76,
                              ),
                          ],
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Left Player Box (My Avatar)
                            _PlayerCardBox(
                              name: myName,
                              avatarUrl: myAvatar,
                              borderColor: const Color(0xFFE53935),
                            ),

                            const SizedBox(width: 12),

                            // Center 3D VS Badge
                            AnimatedBuilder(
                              animation: _vsGlowController,
                              builder: (context, child) {
                                final glow = _vsGlowController.value;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFFEA00),
                                        Color(0xFFFF8F00),
                                        Color(0xFFB76E00)
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFFFD700)
                                            .withValues(
                                                alpha: 0.6 + glow * 0.4),
                                        blurRadius: 12 + glow * 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    'VS',
                                    style: GoogleFonts.poppins(
                                      color: Colors.black87,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                );
                              },
                            ),

                            const SizedBox(width: 12),

                            // Right Player Box (Opponent Avatar or Searching Shimmer)
                            _PlayerCardBox(
                              name: _isMatchFound
                                  ? (_opponentName ?? 'Opponent')
                                  : '???',
                              avatarUrl: _isMatchFound ? _opponentAvatar : null,
                              borderColor: const Color(0xFF1E88E5),
                              isSearching: _hasStartedSearch &&
                                  !_isMatchFound &&
                                  !_searchFailed,
                            ),
                          ],
                        ),

                      const SizedBox(height: 24),

                      // Stopwatch Timer Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFF00E676), width: 2),
                          boxShadow: const [
                            BoxShadow(color: Color(0x8800E676), blurRadius: 10),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_rounded,
                                color: Color(0xFF00E676), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              '$minutes:$seconds',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Searching Text with Pulse Animation
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final opacity = 0.5 + _pulseController.value * 0.5;
                          return Opacity(
                            opacity: opacity,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search_rounded,
                                    color: AppColors.gold, size: 22),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _isMatchFound
                                        ? 'PLAYERS CONNECTED! STARTING...'
                                        : _searchFailed
                                            ? (_searchFailureMessage ??
                                                'NO LIVE MATCH AVAILABLE. TRY AGAIN.')
                                            : !_hasStartedSearch
                                                ? 'SELECT A COIN AMOUNT AND START SEARCHING'
                                                : (_queueNotice ??
                                                    'SEARCHING FOR ${widget.playerCount} HUMAN PLAYERS...'),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      color: _isMatchFound
                                          ? const Color(0xFF00E676)
                                          : _searchFailed
                                              ? Colors.white70
                                              : AppColors.gold,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Back/Cancel Button at Bottom Left
            Positioned(
              left: 16,
              bottom: 16,
              child: GestureDetector(
                onTap: _cancelMatchmaking,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black45,
                          blurRadius: 6,
                          offset: Offset(0, 3)),
                    ],
                  ),
                  child: const Icon(Icons.undo_rounded,
                      color: Colors.black87, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerCardBox extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final Color borderColor;
  final bool isSearching;
  final double size;

  const _PlayerCardBox({
    required this.name,
    this.avatarUrl,
    required this.borderColor,
    this.isSearching = false,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF132B5C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 3),
            boxShadow: [
              BoxShadow(
                  color: borderColor.withValues(alpha: 0.5), blurRadius: 10),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: isSearching
              ? _SearchingShimmerAvatar()
              : _buildAvatarImage(avatarUrl),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 105,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarImage(String? url) {
    if (url == null || url.isEmpty) {
      return const Icon(Icons.person_rounded, color: Colors.white70, size: 48);
    }
    if (url.startsWith('http')) {
      return Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded,
              color: Colors.white70, size: 48));
    }
    return Image.asset(url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.person_rounded, color: Colors.white70, size: 48));
  }
}

class _SearchingShimmerAvatar extends StatefulWidget {
  @override
  State<_SearchingShimmerAvatar> createState() =>
      _SearchingShimmerAvatarState();
}

class _SearchingShimmerAvatarState extends State<_SearchingShimmerAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.3 + _controller.value * 0.5;
        return Container(
          color: Colors.black26,
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: const Icon(Icons.person_search_rounded,
                  color: AppColors.gold, size: 44),
            ),
          ),
        );
      },
    );
  }
}
