import 'dart:async';
import 'dart:math' as math;

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

class BuddyGameRequestDialog extends ConsumerStatefulWidget {
  const BuddyGameRequestDialog({
    super.key,
    required this.friendId,
    required this.friendName,
  });

  final String friendId;
  final String friendName;

  static Future<BuddyGameMatch?> show(
    BuildContext context, {
    required String friendId,
    required String friendName,
  }) =>
      showDialog<BuddyGameMatch>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => BuddyGameRequestDialog(
          friendId: friendId,
          friendName: friendName,
        ),
      );

  @override
  ConsumerState<BuddyGameRequestDialog> createState() =>
      _BuddyGameRequestDialogState();
}

class _BuddyGameRequestDialogState
    extends ConsumerState<BuddyGameRequestDialog> {
  static const _entryFees = [
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
    25000,
    50000,
    100000,
  ];

  int _entryFee = 250;
  GameMode _gameMode = GameMode.classic;
  LudoColor _playerColor = LudoColor.red;
  bool _sending = false;
  bool _cancelling = false;
  String? _inviteId;
  String? _error;
  String? _resultMessage;
  DateTime? _sentAt;
  Timer? _pollTimer;
  bool _pollInFlight = false;
  bool _matchDelivered = false;

  String? get _playerId => ref.read(authControllerProvider).user?.id;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final playerId = _playerId;
    if (playerId == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final sessionId =
        '${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(1 << 32)}';
    try {
      final response = await ref.read(apiClientProvider).post(
            '/friends/${widget.friendId}/game-invites',
            data: {
              'entryFee': _entryFee,
              'selectedColor': _playerColor.name,
              'gameMode': _gameMode.wireValue,
              'sessionId': sessionId,
            },
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final id = response.data is Map ? response.data['id']?.toString() : null;
      if (id == null || !mounted) {
        if (mounted)
          setState(() => _error = 'Could not send the game request.');
        return;
      }
      setState(() {
        _inviteId = id;
        _sentAt = DateTime.now();
      });
      _pollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_pollRequestStatus()),
      );
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? error.response?.data['message']?.toString()
          : null;
      if (mounted)
        setState(() => _error = message ?? 'Could not send the game request.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send the game request.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pollRequestStatus() async {
    final playerId = _playerId;
    final inviteId = _inviteId;
    if (_pollInFlight || playerId == null || inviteId == null || !mounted) {
      return;
    }
    if (DateTime.now().difference(_sentAt ?? DateTime.now()).inSeconds >= 180) {
      _pollTimer?.cancel();
      setState(() => _resultMessage = 'Your buddy did not respond in time.');
      return;
    }
    _pollInFlight = true;
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friends/game-invites/outgoing',
            options: Options(headers: {'X-Player-ID': playerId}),
          );
      final rawEntries = response.data is Map ? response.data['entries'] : null;
      if (rawEntries is! List) return;
      final rawEntry = rawEntries.whereType<Map>().firstWhere(
            (entry) => entry['id']?.toString() == inviteId,
            orElse: () => const {},
          );
      final status = rawEntry['status']?.toString();
      if (status == 'ACCEPTED') {
        _pollTimer?.cancel();
        final match = BuddyGameMatch.parse(rawEntry['match']);
        if (match == null) {
          setState(
              () => _error = 'The buddy game details could not be loaded.');
          return;
        }
        if (mounted) {
          _matchDelivered = true;
          Navigator.of(context, rootNavigator: true).pop(match);
        }
      } else if (status == 'DECLINED') {
        _pollTimer?.cancel();
        final reason = rawEntry['declineReason']?.toString().trim();
        setState(() => _resultMessage = reason == null || reason.isEmpty
            ? '${widget.friendName} declined the game request.'
            : '${widget.friendName} declined: $reason');
      } else if (status == 'EXPIRED') {
        _pollTimer?.cancel();
        setState(() => _resultMessage = 'Your buddy did not respond in time.');
      }
    } catch (_) {
      // Keep polling; the invitation remains available until it expires.
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _cancelRequest() async {
    if (_resultMessage != null) {
      Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    final inviteId = _inviteId;
    final playerId = _playerId;
    if (inviteId != null && playerId != null) {
      setState(() => _cancelling = true);
      try {
        await ref.read(apiClientProvider).delete(
              '/friends/game-invites/$inviteId',
              options: Options(headers: {'X-Player-ID': playerId}),
            );
      } on DioException catch (error) {
        if (error.response?.statusCode == 409) {
          await _pollRequestStatus();
          if (_matchDelivered) return;
        }
        if (mounted) {
          setState(() {
            _error = 'Could not cancel the request. Please try again.';
            _cancelling = false;
          });
        }
        return;
      } catch (_) {
        if (mounted) {
          setState(() {
            _error = 'Could not cancel the request. Please try again.';
            _cancelling = false;
          });
        }
        return;
      }
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _inviteId != null && _resultMessage == null;
    return AlertDialog(
      backgroundColor: const Color(0xFF102447),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Play with ${widget.friendName}',
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!waiting && _resultMessage == null) ...[
            Text(
              'Choose the entry amount for both players.',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _entryFee,
              dropdownColor: const Color(0xFF102447),
              style: GoogleFonts.poppins(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Entry coins',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.gold),
                ),
              ),
              items: _entryFees
                  .map((amount) => DropdownMenuItem(
                        value: amount,
                        child: Text('$amount coins'),
                      ))
                  .toList(growable: false),
              onChanged: _sending
                  ? null
                  : (amount) {
                      if (amount != null) setState(() => _entryFee = amount);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<GameMode>(
              value: _gameMode,
              dropdownColor: const Color(0xFF102447),
              style: GoogleFonts.poppins(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Game mode',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.gold),
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: GameMode.classic,
                  child: Text('Classic'),
                ),
                DropdownMenuItem(
                  value: GameMode.firstKill,
                  child: Text('1st Kill Win'),
                ),
              ],
              onChanged: _sending
                  ? null
                  : (mode) {
                      if (mode != null) setState(() => _gameMode = mode);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<LudoColor>(
              value: _playerColor,
              dropdownColor: const Color(0xFF102447),
              style: GoogleFonts.poppins(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Your player color',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.gold),
                ),
              ),
              items: LudoColor.values
                  .map((color) => DropdownMenuItem(
                        value: color,
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 15, color: color.color),
                            const SizedBox(width: 8),
                            Text(color.displayName),
                          ],
                        ),
                      ))
                  .toList(growable: false),
              onChanged: _sending
                  ? null
                  : (color) {
                      if (color != null) setState(() => _playerColor = color);
                    },
            ),
          ],
          if (waiting) ...[
            const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            ),
            const SizedBox(height: 12),
            Text(
              'Waiting for ${widget.friendName} to accept at $_entryFee coins. You will play ${_playerColor.displayName} in ${_gameMode.displayName} mode…',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
          ],
          if (_resultMessage != null)
            Text(
              _resultMessage!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style:
                  GoogleFonts.poppins(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cancelling ? null : _cancelRequest,
          child: Text(waiting || _inviteId == null ? 'CANCEL' : 'CLOSE'),
        ),
        if (!waiting && _resultMessage == null)
          ElevatedButton(
            onPressed: _sending ? null : _sendRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            ),
            child: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('SEND REQUEST'),
          ),
      ],
    );
  }
}
