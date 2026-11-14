import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class OnlineChatMessage {
  const OnlineChatMessage({
    required this.playerId,
    required this.text,
    required this.sentAt,
  });

  final String playerId;
  final String text;
  final DateTime sentAt;
}

const _presetMessages = <String>[
  'Hi!',
  'Hello!',
  'Play fast!',
  'Okay!',
  'Lucky roll!',
  'Please add me as a buddy!',
  'Catch me if you can!',
  'I have to go. Bye!',
  'I will let you win!',
  'Don’t kill my token!',
  'You should give up!',
  'I am going to win!',
  'Want to play me again?',
  'I am Ludo King!',
  'I need to go, sorry!',
  'Don’t run away!',
  'Some urgent work. Bye!',
  'Why did you hit me?',
  'Game is not over yet!',
  'You can’t beat me!',
  'Bye! Bye!',
  'Hahahaha!',
  'Today is my day!',
  'All the best!',
  'Sorry!',
  'Well played!',
];

class OnlineChatButton extends StatelessWidget {
  const OnlineChatButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Open match chat',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: CustomPaint(
              size: const Size(68, 54),
              painter: _ChatBubbleButtonPainter(),
              child: const SizedBox(
                width: 68,
                height: 54,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 9),
                  child: Icon(Icons.more_horiz_rounded,
                      size: 35, color: Colors.black),
                ),
              ),
            ),
          ),
        ),
      );
}

class OnlineChatMessageBubble extends StatelessWidget {
  const OnlineChatMessageBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(240, 82),
        painter: _ChatBubbleButtonPainter(),
        child: SizedBox(
          width: 240,
          height: 82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 17),
            child: Center(
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF172033),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
}

class _ChatBubbleButtonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final tailHeight = size.height > 60 ? 14.0 : 13.0;
    final bodyBottom = size.height - tailHeight;
    final radius = (bodyBottom / 2).clamp(8.0, 22.0);
    final path = Path()
      ..moveTo(radius + 2, 2)
      ..lineTo(size.width - radius - 2, 2)
      ..quadraticBezierTo(size.width - 2, 2, size.width - 2, radius + 2)
      ..lineTo(size.width - 2, bodyBottom - radius)
      ..quadraticBezierTo(
          size.width - 2, bodyBottom, size.width - radius - 2, bodyBottom)
      ..lineTo(30, bodyBottom)
      ..lineTo(17, size.height - 2)
      ..lineTo(15, bodyBottom)
      ..lineTo(radius + 2, bodyBottom)
      ..quadraticBezierTo(2, bodyBottom, 2, bodyBottom - radius)
      ..lineTo(2, radius + 2)
      ..quadraticBezierTo(2, 2, radius + 2, 2)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ChatBubbleButtonPainter oldDelegate) => false;
}

class OnlineChatSheet extends StatefulWidget {
  const OnlineChatSheet({
    super.key,
    required this.messages,
    required this.localPlayerId,
    required this.playerNames,
    required this.onSend,
  });

  final ValueListenable<List<OnlineChatMessage>> messages;
  final String localPlayerId;
  final Map<String, String> playerNames;
  final ValueChanged<String> onSend;

  static Future<void> show(
    BuildContext context, {
    required ValueListenable<List<OnlineChatMessage>> messages,
    required String localPlayerId,
    required Map<String, String> playerNames,
    required ValueChanged<String> onSend,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => OnlineChatSheet(
        messages: messages,
        localPlayerId: localPlayerId,
        playerNames: playerNames,
        onSend: onSend,
      ),
    );
  }

  @override
  State<OnlineChatSheet> createState() => _OnlineChatSheetState();
}

class _OnlineChatSheetState extends State<OnlineChatSheet> {
  final _textController = TextEditingController();
  final _inputFocusNode = FocusNode();
  bool _showPresets = true;

  @override
  void dispose() {
    _textController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _send(String text) {
    final message = text.trim();
    if (message.isEmpty || message.length > 200) return;
    widget.onSend(message);
    _textController.clear();
    _inputFocusNode.unfocus();
    Navigator.of(context).pop();
  }

  void _sendPreset(String text) {
    final message = text.trim();
    if (message.isEmpty) return;
    widget.onSend(message);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFF4F5F7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: const BoxDecoration(
                color: Color(0xFF57B5EC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  _headerTab(
                    icon: Icons.chat_bubble_rounded,
                    tooltip: 'Preset messages',
                    selected: _showPresets,
                    onPressed: () {
                      setState(() => _showPresets = true);
                      _inputFocusNode.unfocus();
                    },
                  ),
                  _headerTab(
                    icon: Icons.keyboard_alt_rounded,
                    tooltip: 'Type a message',
                    selected: !_showPresets,
                    onPressed: () {
                      setState(() => _showPresets = false);
                      _inputFocusNode.requestFocus();
                    },
                  ),
                  Expanded(
                    child: Text(
                      _showPresets ? 'Preset' : 'Chat',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(color: Color(0x66000000), blurRadius: 3),
                        ],
                      ),
                    ),
                  ),
                  Material(
                    color: const Color(0xFFE31B23),
                    shape: const CircleBorder(
                      side: BorderSide(color: Colors.white, width: 2),
                    ),
                    elevation: 2,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close chat',
                      constraints:
                          const BoxConstraints.tightFor(width: 40, height: 40),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _showPresets ? _buildPresetGrid() : _buildConversation(),
            ),
            if (!_showPresets) _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _headerTab({
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onPressed,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 5),
        child: Material(
          color: selected ? const Color(0xFF1985C5) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: IconButton(
            onPressed: onPressed,
            tooltip: tooltip,
            icon: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      );

  Widget _buildPresetGrid() => GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 2.65,
        ),
        itemCount: _presetMessages.length,
        itemBuilder: (context, index) => Material(
          color: const Color(0xFF123B86),
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => _sendPreset(_presetMessages[index]),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                child: Text(
                  _presetMessages[index],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildConversation() =>
      ValueListenableBuilder<List<OnlineChatMessage>>(
        valueListenable: widget.messages,
        builder: (context, messages, _) {
          if (messages.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text('No messages yet. Say hello!'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            reverse: true,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[messages.length - 1 - index];
              final isMine = message.playerId == widget.localPlayerId;
              final name = widget.playerNames[message.playerId] ?? 'Player';
              return Align(
                alignment:
                    isMine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMine ? const Color(0xFF123B86) : Colors.white,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!isMine)
                        Text(name,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF315C9B))),
                      Text(message.text,
                          style: TextStyle(
                            color:
                                isMine ? Colors.white : const Color(0xFF18243A),
                          )),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

  Widget _buildComposer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 5, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _inputFocusNode,
                  style: const TextStyle(
                    color: Color(0xFF18243A),
                    fontSize: 16,
                  ),
                  cursorColor: const Color(0xFF123B86),
                  maxLength: 200,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: 'Write a message…',
                    hintStyle: const TextStyle(color: Color(0xFF667085)),
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFFD4D9E2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(
                          color: Color(0xFF123B86), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _send(_textController.text),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF123B86),
                  foregroundColor: Colors.white,
                ),
                tooltip: 'Send message',
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      );
}
