import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  String? get _playerId => ref.read(authControllerProvider).user?.id;

  Options get _playerOptions => Options(
        headers: {'X-Player-ID': _playerId},
      );

  Future<void> _loadFriends() async {
    final playerId = _playerId;
    if (playerId == null) {
      if (mounted) setState(() { _loading = false; _error = 'Sign in to view friends.'; });
      return;
    }
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends',
            options: _playerOptions,
          );
      final data = response.data;
      final rawEntries = data is Map ? data['entries'] : null;
      final entries = rawEntries is List
          ? rawEntries.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() { _friends = entries; _loading = false; _error = null; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load your friends.'; });
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
          ? error.response?.data['message']?.toString() ?? 'Could not accept request.'
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
          ? error.response?.data['message']?.toString() ?? 'Could not remove friend.'
          : 'Could not remove friend.');
    }
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
              ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, style: GoogleFonts.poppins(color: Colors.white70)),
                          TextButton(onPressed: _loadFriends, child: const Text('RETRY')),
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
                              final friendshipId = friend['id']?.toString() ?? '';
                              return ListTile(
                                onTap: status == 'ACCEPTED'
                                    ? () async {
                                        await FriendChatDialog.show(
                                          context,
                                          friendId: friend['playerId']?.toString() ?? '',
                                          friendName:
                                              friend['displayName']?.toString() ?? 'Player',
                                        );
                                        await _loadFriends();
                                      }
                                    : null,
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF19345F),
                                  child: Text(
                                    friend['countryFlag']?.toString() ?? '🌐',
                                    style: const TextStyle(fontSize: 19),
                                  ),
                                ),
                                title: Text(
                                  friend['displayName']?.toString() ?? 'Player',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(
                                  incoming
                                      ? 'Wants to be your friend'
                                      : status == 'ACCEPTED'
                                          ? 'Friend'
                                          : 'Request sent',
                                  style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
                                ),
                                trailing: incoming
                                    ? TextButton(
                                        onPressed: () => _accept(friendshipId),
                                        child: const Text('ACCEPT'),
                                      )
                                    : status == 'ACCEPTED'
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Chat',
                                                onPressed: () => FriendChatDialog.show(
                                                  context,
                                                  friendId:
                                                      friend['playerId']?.toString() ?? '',
                                                  friendName: friend['displayName']
                                                          ?.toString() ??
                                                      'Player',
                                                ),
                                                icon: const Icon(
                                                  Icons.chat_bubble_outline_rounded,
                                                  color: AppColors.gold,
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                tooltip: 'Friend options',
                                                onSelected: (value) {
                                                  if (value == 'remove') _remove(friendshipId);
                                                },
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                    value: 'remove',
                                                    child: Text('Remove friend'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          )
                                    : IconButton(
                                        tooltip: status == 'ACCEPTED' ? 'Remove friend' : 'Cancel request',
                                        onPressed: () => _remove(friendshipId),
                                        icon: const Icon(Icons.person_remove_alt_1_rounded,
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
