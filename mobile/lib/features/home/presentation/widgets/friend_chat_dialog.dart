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
  static final Set<String> openFriendIds = <String>{};

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
        useRootNavigator: true,
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
    FriendChatDialog.openFriendIds.add(widget.friendId);
    ref.read(voiceCallServiceProvider).addListener(_handleVoiceCallChanged);
    _loadMessages();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadMessages(silent: true),
    );
  }

  @override
  void dispose() {
    FriendChatDialog.openFriendIds.remove(widget.friendId);
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
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign in to use friend chat.';
        });
      }
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
      final wasNearBottom = !_scrollController.hasClients ||
          _scrollController.position.maxScrollExtent -
                  _scrollController.position.pixels <
              96;
      final previousLastId = _messages.isEmpty ? null : _messages.last['id'];
      final nextLastId = messages.isEmpty ? null : messages.last['id'];
      final hasNewMessages = nextLastId != null && nextLastId != previousLastId;
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
      if (hasNewMessages && wasNearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
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
      if (mounted) {
        setState(() => _error = message ?? 'Message could not be sent.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Message could not be sent.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  DateTime? _createdAt(Map<String, dynamic> message) =>
      DateTime.tryParse(message['createdAt']?.toString() ?? '')?.toLocal();

  bool _sameDay(DateTime? first, DateTime? second) =>
      first != null &&
      second != null &&
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Earlier';
    final today = DateTime.now();
    if (_sameDay(date, today)) return 'Today';
    if (_sameDay(date, today.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _timeLabel(DateTime? date) {
    if (date == null) return '';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool _sameMessageCluster(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    if (first['senderId'] != second['senderId']) return false;
    final firstTime = _createdAt(first);
    final secondTime = _createdAt(second);
    if (firstTime == null || secondTime == null) return true;
    return _sameDay(firstTime, secondTime) &&
        secondTime.difference(firstTime).abs() <= const Duration(minutes: 2);
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
    final viewport = MediaQuery.sizeOf(context);
    final initials = widget.friendName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    final timeline = <Widget>[];
    for (var index = 0; index < _messages.length; index++) {
      final message = _messages[index];
      final time = _createdAt(message);
      if (index == 0 || !_sameDay(_createdAt(_messages[index - 1]), time)) {
        timeline.add(_ChatDateDivider(label: _dateLabel(time)));
      }
      final previousSameCluster =
          index > 0 && _sameMessageCluster(_messages[index - 1], message);
      final nextSameCluster = index + 1 < _messages.length &&
          _sameMessageCluster(message, _messages[index + 1]);
      timeline.add(
        _FriendMessageBubble(
          content: message['content']?.toString() ?? '',
          time: _timeLabel(time),
          mine: message['senderId'] == playerId,
          firstInCluster: !previousSameCluster,
          lastInCluster: !nextSameCluster,
          maxWidth: viewport.width * 0.78,
        ),
      );
    }

    return Dialog(
      backgroundColor: const Color(0xFF081B22),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 500,
        height: (viewport.height * 0.88).clamp(440.0, 760.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF123B3B), Color(0xFF102A36)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: const Color(0xFF1F6D62),
                    child: Text(
                      initials.isEmpty ? '?' : initials,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.friendName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'FRIEND CHAT',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFB0CDC7),
                            fontSize: 10,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF482F20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFFFD7A3),
                    fontSize: 12,
                  ),
                ),
              ),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0B2027), Color(0xFF0D252B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.gold),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.waving_hand_rounded,
                                    color: AppColors.gold,
                                    size: 38,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Say hello to ${widget.friendName}.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                            children: timeline,
                          ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                12,
                10,
                12,
                10 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF102A30),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Message',
                        hintStyle: GoogleFonts.poppins(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF1A3439),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 17,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Material(
                    color: const Color(0xFF1F9B72),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Send message',
                      onPressed: _sending ? null : _sendMessage,
                      color: Colors.white,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
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

class _ChatDateDivider extends StatelessWidget {
  final String label;

  const _ChatDateDivider({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF24434A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  color: const Color(0xFFC4D7D4),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
}

class _FriendMessageBubble extends StatelessWidget {
  final String content;
  final String time;
  final bool mine;
  final bool firstInCluster;
  final bool lastInCluster;
  final double maxWidth;

  const _FriendMessageBubble({
    required this.content,
    required this.time,
    required this.mine,
    required this.firstInCluster,
    required this.lastInCluster,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: Radius.circular(mine || firstInCluster ? 17 : 7),
      topRight: Radius.circular(!mine || firstInCluster ? 17 : 7),
      bottomLeft: Radius.circular(mine || lastInCluster ? 17 : 7),
      bottomRight: Radius.circular(!mine || lastInCluster ? 17 : 7),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: EdgeInsets.only(
          top: firstInCluster ? 5 : 1,
          bottom: lastInCluster ? 5 : 1,
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 5),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF075E54) : const Color(0xFF1B3339),
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                content,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.38,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: GoogleFonts.poppins(
                      color: Colors.white60,
                      fontSize: 9,
                    ),
                  ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.done_rounded,
                    size: 13,
                    color: Color(0xFFB7C9C8),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
