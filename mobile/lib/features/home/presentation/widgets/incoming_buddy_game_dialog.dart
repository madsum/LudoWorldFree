import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../game/domain/models/game_mode.dart';
import '../../../game/domain/models/ludo_color.dart';
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
  final _declineReasonController = TextEditingController();
  bool _working = false;
  bool _declining = false;
  String? _error;
  LudoColor? _selectedColor;

  String? get _playerId => ref.read(authControllerProvider).user?.id;

  @override
  void dispose() {
    _declineReasonController.dispose();
    super.dispose();
  }

  String _acceptErrorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      for (final key in const ['message', 'detail', 'error_description']) {
        final value = data[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    final statusCode = error.response?.statusCode;
    if (statusCode == 409) {
      return 'This game request expired, a player is already in a game, or one player needs more coins.';
    }
    if (error.response == null) {
      return 'Could not reach the game server. Check your connection and try again.';
    }
    return 'Could not accept the game request (server error $statusCode).';
  }

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
    final requesterColor = LudoColor.values.firstWhere(
      (color) => color.name == widget.invitation['requesterColor']?.toString(),
      orElse: () => LudoColor.red,
    );
    final selectedColor = _selectedColor ?? _defaultTargetColor(requesterColor);
    try {
      final response = await ref.read(apiClientProvider).post(
            '/friends/game-invites/$inviteId/accept',
            data: {'sessionId': sessionId, 'selectedColor': selectedColor.name},
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
      if (mounted) setState(() => _error = _acceptErrorMessage(error));
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not accept the game request.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  LudoColor _defaultTargetColor(LudoColor requesterColor) =>
      switch (requesterColor) {
        LudoColor.red => LudoColor.yellow,
        LudoColor.green => LudoColor.blue,
        LudoColor.yellow => LudoColor.red,
        LudoColor.blue => LudoColor.green,
      };

  Future<void> _decline() async {
    final playerId = _playerId;
    final inviteId = widget.invitation['id']?.toString();
    if (playerId == null || inviteId == null || _working) return;
    final reason = _declineReasonController.text.trim();
    if (reason.isEmpty) {
      setState(() {
        _declining = true;
        _error = 'Please write a short reason before declining.';
      });
      return;
    }
    setState(() => _working = true);
    try {
      await ref.read(apiClientProvider).post(
            '/friends/game-invites/$inviteId/decline',
            data: {'reason': reason},
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
    final gameMode = GameMode.fromWireValue(widget.invitation['gameMode']);
    final inviterColor = LudoColor.values.firstWhere(
      (color) => color.name == widget.invitation['requesterColor']?.toString(),
      orElse: () => LudoColor.red,
    );
    final availableColors = LudoColor.values
        .where((color) => color != inviterColor)
        .toList(growable: false);
    final selectedColor = _selectedColor ?? _defaultTargetColor(inviterColor);
    final inGame = widget.invitation['inGame'] == true;
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
            '$name invited you to a two-player ${gameMode.displayName} game for $amount coins. They chose ${inviterColor.displayName}. Choose your color below. Both players use the same entry amount.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in availableColors)
                ChoiceChip(
                  selected: selectedColor == color,
                  onSelected: _working
                      ? null
                      : (_) => setState(() {
                            _selectedColor = color;
                            _error = null;
                          }),
                  avatar: CircleAvatar(
                    radius: 8,
                    backgroundColor: color.color,
                  ),
                  label: Text(color.displayName),
                  selectedColor: color.color.withOpacity(0.25),
                  labelStyle: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                  side: BorderSide(
                    color: selectedColor == color
                        ? color.lightColor
                        : Colors.white30,
                  ),
                ),
            ],
          ),
          if (inGame) ...[
            const SizedBox(height: 10),
            Text(
              'You are in another game. Accepting will forfeit that game and join this one.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.orangeAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_declining) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _declineReasonController,
              maxLength: 500,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Why are you declining?',
                hintText: 'Write a short message for your buddy',
                border: OutlineInputBorder(),
                counterStyle: TextStyle(color: Colors.white54),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
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
        if (_declining)
          TextButton(
            onPressed: _working
                ? null
                : () => setState(() {
                      _declining = false;
                      _error = null;
                    }),
            child: const Text('BACK'),
          )
        else
          TextButton(
            onPressed: _working
                ? null
                : () => setState(() {
                      _declining = true;
                      _error = null;
                    }),
            child: const Text('DECLINE'),
          ),
        ElevatedButton(
          onPressed: _working ? null : (_declining ? _decline : _accept),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
          ),
          child: _working
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_declining ? 'SEND REASON' : 'ACCEPT & PLAY'),
        ),
      ],
    );
  }
}
