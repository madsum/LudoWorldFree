import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../game/presentation/services/voice_call_service.dart';

class FriendChatDialog extends ConsumerStatefulWidget {
  final String friendId;
  final String friendName;

  const FriendChatDialog({
    super.key,
    required this.friendId,
    required this.friendName,
  });

  static Future<void> show(
    BuildContext context, {
    required String friendId,
    required String friendName,
  }) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            FriendChatDialog(friendId: friendId, friendName: friendName),
      );

  @override
  ConsumerState<FriendChatDialog> createState() => _FriendChatDialogState();
}

class _FriendChatDialogState extends ConsumerState<FriendChatDialog> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = const [];
  Timer? _refreshTimer;
  bool _loading = true;
  bool _sending = false;
  bool _outgoingCallPending = false;
  String? _error;

  String? get _playerId => ref.read(authControllerProvider).user?.id;
  Options get _playerOptions => Options(headers: {'X-Player-ID': _playerId});
  String get _messagesPath => '/friends/${widget.friendId}/messages';

  @override
  void initState() {
    super.initState();
    ref.read(voiceCallServiceProvider).addListener(_handleVoiceCallChanged);
    _loadMessages();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadMessages(silent: true),
    );
  }

  @override
  void dispose() {
    ref.read(voiceCallServiceProvider).removeListener(_handleVoiceCallChanged);
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleVoiceCallChanged() {
    final currentCall = ref.read(voiceCallServiceProvider).call;
    if (currentCall?.peerId != widget.friendId) {
      if (currentCall == null) _outgoingCallPending = false;
      return;
    }
    if (currentCall!.phase == VoiceCallPhase.outgoing) {
      _outgoingCallPending = true;
      return;
    }
    if (_outgoingCallPending &&
        (currentCall.phase == VoiceCallPhase.connecting ||
            currentCall.phase == VoiceCallPhase.connected)) {
      _outgoingCallPending = false;
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_playerId == null) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Sign in to use friend chat.';
        });
      return;
    }
    try {
      final response = await ref.read(apiClientProvider).get(
            _messagesPath,
            options: _playerOptions,
          );
      final raw = response.data is Map ? response.data['messages'] : null;
      final messages = raw is List
          ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this conversation.';
      });
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _sending) return;
    if (_playerId == null) {
      setState(() => _error = 'Sign in to send messages.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).post(
            _messagesPath,
            data: {'content': content},
            options: _playerOptions,
          );
      _messageController.clear();
      await _loadMessages(silent: true);
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? error.response?.data['message']?.toString()
          : null;
      if (mounted)
        setState(() => _error = message ?? 'Message could not be sent.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Message could not be sent.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startVoiceCall() async {
    try {
      await ref
          .read(voiceCallServiceProvider)
          .startCall(widget.friendId, widget.friendName);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Bad state: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerId = _playerId;
    final voiceCall = ref.watch(voiceCallServiceProvider).call;
    final callingThisFriend = voiceCall?.peerId == widget.friendId;
    return Dialog(
      backgroundColor: const Color(0xFF102447),
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 430,
        height: 540,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_rounded, color: AppColors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.friendName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: callingThisFriend
                        ? 'End voice call'
                        : 'Call this buddy',
                    onPressed: callingThisFriend
                        ? () => ref.read(voiceCallServiceProvider).endCall()
                        : _startVoiceCall,
                    icon: Icon(
                      callingThisFriend
                          ? Icons.call_end_rounded
                          : Icons.call_rounded,
                      color:
                          callingThisFriend ? Colors.redAccent : AppColors.gold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!,
                    style: GoogleFonts.poppins(
                        color: Colors.orangeAccent, fontSize: 12)),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.gold))
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            'Say hello to ${widget.friendName}.',
                            style: GoogleFonts.poppins(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(14),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final mine = message['senderId'] == playerId;
                            return Align(
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 290),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? const Color(0xFF8F6511)
                                      : const Color(0xFF1B355A),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  message['content']?.toString() ?? '',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Write a message',
                        hintStyle: GoogleFonts.poppins(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF091A35),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                    ),
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
