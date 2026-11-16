import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../game/domain/models/player_model.dart';
import 'friend_chat_dialog.dart';

class PlayerBuddyProfileDialog extends ConsumerStatefulWidget {
  final PlayerModel player;

  const PlayerBuddyProfileDialog({super.key, required this.player});

  static Future<void> show(BuildContext context, PlayerModel player) =>
      showDialog<void>(
        context: context,
        builder: (_) => PlayerBuddyProfileDialog(player: player),
      );

  @override
  ConsumerState<PlayerBuddyProfileDialog> createState() =>
      _PlayerBuddyProfileDialogState();
}

class _PlayerBuddyProfileDialogState
    extends ConsumerState<PlayerBuddyProfileDialog> {
  Map<String, dynamic>? _relationship;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? get _playerId => ref.read(authControllerProvider).user?.id;
  Options get _playerOptions => Options(headers: {'X-Player-ID': _playerId});

  @override
  void initState() {
    super.initState();
    _loadRelationship();
  }

  Future<void> _loadRelationship() async {
    final playerId = _playerId;
    if (playerId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign in to connect with players.';
        });
      }
      return;
    }
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends',
            options: _playerOptions,
          );
      final raw = response.data is Map ? response.data['entries'] : null;
      final relationship = raw is List
          ? raw
              .whereType<Map>()
              .cast<Map>()
              .map(Map<String, dynamic>.from)
              .firstWhere(
                (entry) => entry['playerId']?.toString() == widget.player.id,
                orElse: () => <String, dynamic>{},
              )
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _relationship = relationship.isEmpty ? null : relationship;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load friend status.';
      });
    }
  }

  Future<void> _sendRequest() async {
    await _runAction(() async {
      final response = await ref.read(apiClientProvider).post(
            '/friends/requests',
            data: {'playerId': widget.player.id},
            options: _playerOptions,
          );
      final data = response.data;
      await _loadRelationship();
      if (mounted && data is Map && data['status'] == 'ACCEPTED') {
        _showMessage('You are now buddies.');
      } else if (mounted) {
        _showMessage('Buddy request sent.');
      }
    });
  }

  Future<void> _acceptRequest() async {
    final friendshipId = _relationship?['id']?.toString();
    if (friendshipId == null) return;
    await _runAction(() async {
      await ref.read(apiClientProvider).post(
            '/friends/$friendshipId/accept',
            options: _playerOptions,
          );
      await _loadRelationship();
      if (mounted) _showMessage('Buddy request accepted.');
    });
  }

  Future<void> _declineOrCancel() async {
    final friendshipId = _relationship?['id']?.toString();
    if (friendshipId == null) return;
    await _runAction(() async {
      await ref.read(apiClientProvider).delete(
            '/friends/$friendshipId',
            options: _playerOptions,
          );
      await _loadRelationship();
      if (mounted) _showMessage('Buddy request declined.');
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? error.response?.data['message']?.toString()
          : null;
      if (mounted) _showMessage(message ?? 'Could not update buddy request.');
    } catch (_) {
      if (mounted) _showMessage('Could not update buddy request.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openChat() async {
    await FriendChatDialog.show(
      context,
      friendId: widget.player.id,
      friendName: widget.player.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final relationship = _relationship;
    final status = relationship?['status']?.toString();
    final incoming =
        status == 'PENDING' && relationship?['direction'] == 'INCOMING';
    final accepted = status == 'ACCEPTED';

    return Dialog(
      backgroundColor: const Color(0xFF102447),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              heightFactor: 0.5,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ),
            CircleAvatar(
              radius: 42,
              backgroundColor: widget.player.color.color.withValues(alpha: 0.2),
              child: ClipOval(
                child: widget.player.avatarUrl == null
                    ? Text(widget.player.countryFlag,
                        style: const TextStyle(fontSize: 34))
                    : _buildAvatar(widget.player.avatarUrl!),
              ),
            ),
            const SizedBox(height: 10),
            Text(widget.player.name,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800)),
            Text('${widget.player.countryFlag}  ${widget.player.country}',
                style:
                    GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 20),
            if (_loading)
              const CircularProgressIndicator(color: AppColors.gold)
            else if (_error != null)
              TextButton(onPressed: _loadRelationship, child: Text(_error!))
            else if (incoming)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _declineOrCancel,
                      child: const Text('DECLINE'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _acceptRequest,
                      child: const Text('ACCEPT'),
                    ),
                  ),
                ],
              )
            else if (accepted)
              FilledButton.icon(
                onPressed: _openChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('CHAT WITH BUDDY'),
              )
            else if (status == 'PENDING')
              OutlinedButton.icon(
                onPressed: _saving ? null : _declineOrCancel,
                icon: const Icon(Icons.hourglass_top_rounded),
                label: const Text('REQUEST SENT · CANCEL'),
              )
            else
              FilledButton.icon(
                onPressed: _saving ? null : _sendRequest,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('ASK TO BE BUDDIES'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String avatarUrl) {
    final fallback = Text(
      widget.player.countryFlag,
      style: const TextStyle(fontSize: 34),
    );
    if (avatarUrl.startsWith('http')) {
      return Image.network(
        avatarUrl,
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    if (avatarUrl.startsWith('assets/') || avatarUrl.endsWith('.webp')) {
      return Image.asset(
        avatarUrl,
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }
}
