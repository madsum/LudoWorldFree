import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import 'buddy_game_match.dart';

class IncomingBuddyGameDialog extends ConsumerStatefulWidget {
  const IncomingBuddyGameDialog({
    super.key,
    required this.invitation,
  });

  final Map<String, dynamic> invitation;

  static Future<BuddyGameMatch?> show(
    BuildContext context, {
    required Map<String, dynamic> invitation,
  }) =>
      showDialog<BuddyGameMatch>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => IncomingBuddyGameDialog(invitation: invitation),
      );

  @override
  ConsumerState<IncomingBuddyGameDialog> createState() =>
      _IncomingBuddyGameDialogState();
}

class _IncomingBuddyGameDialogState
    extends ConsumerState<IncomingBuddyGameDialog> {
  bool _working = false;
  String? _error;

  String? get _playerId => ref.read(authControllerProvider).user?.id;

  Future<void> _accept() async {
    final playerId = _playerId;
    final inviteId = widget.invitation['id']?.toString();
    if (playerId == null || inviteId == null || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final sessionId =
        '${DateTime.now().microsecondsSinceEpoch}_${playerId.hashCode.abs()}';
    try {
      final response = await ref.read(apiClientProvider).post(
            '/friends/game-invites/$inviteId/accept',
            data: {'sessionId': sessionId},
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final match = BuddyGameMatch.parse(
        response.data is Map ? response.data['match'] : null,
      );
      if (match == null) {
        if (mounted)
          setState(() => _error = 'Could not prepare the buddy game.');
        return;
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop(match);
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? error.response?.data['message']?.toString()
          : null;
      if (mounted)
        setState(
            () => _error = message ?? 'Could not accept the game request.');
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not accept the game request.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _decline() async {
    final playerId = _playerId;
    final inviteId = widget.invitation['id']?.toString();
    if (playerId == null || inviteId == null || _working) return;
    setState(() => _working = true);
    try {
      await ref.read(apiClientProvider).post(
            '/friends/game-invites/$inviteId/decline',
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? error.response?.data['message']?.toString()
          : null;
      if (mounted)
        setState(
            () => _error = message ?? 'Could not decline the game request.');
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not decline the game request.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.invitation['displayName']?.toString() ?? 'Your buddy';
    final amount = (widget.invitation['entryFee'] as num?)?.toInt() ?? 0;
    return AlertDialog(
      backgroundColor: const Color(0xFF102447),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Buddy game request',
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$name invited you to a two-player game for $amount coins. Both players will use this entry amount.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white70),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style:
                  GoogleFonts.poppins(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : _decline,
          child: const Text('DECLINE'),
        ),
        ElevatedButton(
          onPressed: _working ? null : _accept,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
          ),
          child: _working
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ACCEPT & PLAY'),
        ),
      ],
    );
  }
}
