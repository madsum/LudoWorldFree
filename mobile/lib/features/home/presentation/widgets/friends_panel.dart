import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_service.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../game/presentation/controllers/game_controller.dart';
import '../../../game/presentation/services/voice_call_service.dart';
import 'buddy_game_match.dart';
import 'buddy_game_request_dialog.dart';
import 'friend_chat_dialog.dart';

class FriendsPanel extends ConsumerStatefulWidget {
  const FriendsPanel({super.key});

  @override
  ConsumerState<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends ConsumerState<FriendsPanel> {
  final _usernameController = TextEditingController();
  List<Map<String, dynamic>> _friends = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Timer? _refreshTimer;
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _loadFriends(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  String? get _playerId => ref.read(authControllerProvider).user?.id;

  Options get _playerOptions => Options(
        headers: {'X-Player-ID': _playerId},
      );

  Future<void> _loadFriends() async {
    if (_requestInFlight) return;
    final playerId = _playerId;
    if (playerId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign in to view friends.';
        });
      }
      return;
    }
    _requestInFlight = true;
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends',
            options: _playerOptions,
          );
      final data = response.data;
      final rawEntries = data is Map ? data['entries'] : null;
      final entries = rawEntries is List
          ? rawEntries
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _friends = entries;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your friends.';
      });
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _sendRequest() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty || _submitting) return;
    if (_playerId == null) {
      _showMessage('Sign in before adding friends.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      final playerResponse = await dio.get(
        '/player/username',
        queryParameters: {'username': username},
      );
      final targetId = playerResponse.data is Map
          ? playerResponse.data['playerId']?.toString()
          : null;
      if (targetId == null || targetId.isEmpty) {
        throw const FormatException('Player response did not include an ID.');
      }
      final requestResponse = await dio.post(
        '/friends/requests',
        data: {'playerId': targetId},
        options: _playerOptions,
      );
      final status = requestResponse.data is Map
          ? requestResponse.data['status']?.toString()
          : null;
      _usernameController.clear();
      _showMessage(status == 'ACCEPTED'
          ? 'Friend request accepted.'
          : status == 'PENDING'
              ? 'Friend request sent.'
              : 'You are already friends.');
      await _loadFriends();
    } on DioException catch (error) {
      final responseMessage = error.response?.data is Map
          ? error.response?.data['message']?.toString()
          : null;
      _showMessage(responseMessage ?? 'Could not send friend request.');
    } catch (_) {
      _showMessage('Could not find that player. Check the username.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _accept(String friendshipId) async {
    try {
      await ref.read(apiClientProvider).post(
            '/friends/$friendshipId/accept',
            options: _playerOptions,
          );
      await _loadFriends();
    } on DioException catch (error) {
      _showMessage(error.response?.data is Map
          ? error.response?.data['message']?.toString() ??
              'Could not accept request.'
          : 'Could not accept request.');
    }
  }

  Future<void> _remove(String friendshipId) async {
    try {
      await ref.read(apiClientProvider).delete(
            '/friends/$friendshipId',
            options: _playerOptions,
          );
      await _loadFriends();
    } on DioException catch (error) {
      _showMessage(error.response?.data is Map
          ? error.response?.data['message']?.toString() ??
              'Could not remove friend.'
          : 'Could not remove friend.');
    }
  }

  Future<void> _callFriend(Map<String, dynamic> friend) async {
    try {
      await ref.read(voiceCallServiceProvider).startCall(
            friend['playerId']?.toString() ?? '',
            friend['displayName']?.toString() ?? 'Buddy',
          );
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _requestBuddyGame(Map<String, dynamic> friend) async {
    final friendId = friend['playerId']?.toString() ?? '';
    if (friendId.isEmpty) return;
    final match = await BuddyGameRequestDialog.show(
      context,
      friendId: friendId,
      friendName: friend['displayName']?.toString() ?? 'Buddy',
    );
    if (match != null && mounted) await _startBuddyGame(match);
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
      _showMessage('Could not connect to the buddy game. Please try again.');
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF142547),
        content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final currentVoiceCall = ref.watch(voiceCallServiceProvider).call;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded,
                  color: AppColors.gold, size: 25),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _sendRequest(),
                  style: GoogleFonts.poppins(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search exact username',
                    hintStyle: GoogleFonts.poppins(color: Colors.white38),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF142547),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _submitting ? null : _sendRequest,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                ),
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white24),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.gold))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              style:
                                  GoogleFonts.poppins(color: Colors.white70)),
                          TextButton(
                              onPressed: _loadFriends,
                              child: const Text('RETRY')),
                        ],
                      ),
                    )
                  : _friends.isEmpty
                      ? Center(
                          child: Text(
                            'No friends yet. Search a username to connect.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(color: Colors.white54),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadFriends,
                          color: AppColors.gold,
                          child: ListView.separated(
                            itemCount: _friends.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, color: Colors.white10),
                            itemBuilder: (context, index) {
                              final friend = _friends[index];
                              final status = friend['status']?.toString();
                              final incoming = status == 'PENDING' &&
                                  friend['direction'] == 'INCOMING';
                              final isOnline = status == 'ACCEPTED' &&
                                  friend['online'] == true;
                              final friendshipId =
                                  friend['id']?.toString() ?? '';
                              return ListTile(
                                onTap: status == 'ACCEPTED'
                                    ? () async {
                                        await FriendChatDialog.show(
                                          context,
                                          friendId:
                                              friend['playerId']?.toString() ??
                                                  '',
                                          friendName: friend['displayName']
                                                  ?.toString() ??
                                              'Player',
                                        );
                                        await _loadFriends();
                                      }
                                    : null,
                                leading: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: const Color(0xFF19345F),
                                      child: Text(
                                        friend['countryFlag']?.toString() ??
                                            '🌐',
                                        style: const TextStyle(fontSize: 19),
                                      ),
                                    ),
                                    if (isOnline)
                                      Positioned(
                                        right: -1,
                                        bottom: -1,
                                        child: Container(
                                          width: 13,
                                          height: 13,
                                          decoration: BoxDecoration(
                                            color: Colors.greenAccent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: const Color(0xFF08122C),
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text(
                                  friend['displayName']?.toString() ?? 'Player',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(
                                  incoming
                                      ? 'Wants to be your friend'
                                      : status == 'ACCEPTED'
                                          ? 'Friend'
                                          : 'Request sent',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white54, fontSize: 11),
                                ),
                                trailing: incoming
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextButton(
                                            onPressed: () =>
                                                _remove(friendshipId),
                                            child: const Text('DECLINE'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                _accept(friendshipId),
                                            child: const Text('ACCEPT'),
                                          ),
                                        ],
                                      )
                                    : status == 'ACCEPTED'
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Chat',
                                                onPressed: () =>
                                                    FriendChatDialog.show(
                                                  context,
                                                  friendId: friend['playerId']
                                                          ?.toString() ??
                                                      '',
                                                  friendName:
                                                      friend['displayName']
                                                              ?.toString() ??
                                                          'Player',
                                                ),
                                                icon: const Icon(
                                                  Icons
                                                      .chat_bubble_outline_rounded,
                                                  color: AppColors.gold,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: isOnline
                                                    ? 'Play a game with this buddy'
                                                    : 'Buddy is offline',
                                                onPressed: isOnline
                                                    ? () => _requestBuddyGame(
                                                        friend)
                                                    : null,
                                                icon: Icon(
                                                  Icons.sports_esports_rounded,
                                                  color: isOnline
                                                      ? Colors.greenAccent
                                                      : Colors.white24,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip:
                                                    currentVoiceCall?.peerId ==
                                                            friend['playerId']
                                                                ?.toString()
                                                        ? 'End voice call'
                                                        : 'Call buddy',
                                                onPressed: () {
                                                  if (currentVoiceCall
                                                          ?.peerId ==
                                                      friend['playerId']
                                                          ?.toString()) {
                                                    ref
                                                        .read(
                                                            voiceCallServiceProvider)
                                                        .endCall();
                                                  } else {
                                                    _callFriend(friend);
                                                  }
                                                },
                                                icon: Icon(
                                                  currentVoiceCall?.peerId ==
                                                          friend['playerId']
                                                              ?.toString()
                                                      ? Icons.call_end_rounded
                                                      : Icons.call_rounded,
                                                  color: currentVoiceCall
                                                              ?.peerId ==
                                                          friend['playerId']
                                                              ?.toString()
                                                      ? Colors.redAccent
                                                      : Colors.greenAccent,
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                tooltip: 'Friend options',
                                                onSelected: (value) {
                                                  if (value == 'remove') {
                                                    _remove(friendshipId);
                                                  }
                                                },
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                    value: 'remove',
                                                    child:
                                                        Text('Remove friend'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          )
                                        : IconButton(
                                            tooltip: status == 'ACCEPTED'
                                                ? 'Remove friend'
                                                : 'Cancel request',
                                            onPressed: () =>
                                                _remove(friendshipId),
                                            icon: const Icon(
                                                Icons
                                                    .person_remove_alt_1_rounded,
                                                color: Colors.white54),
                                          ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
