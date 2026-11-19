import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EmojiPickerDialog extends StatelessWidget {
  const EmojiPickerDialog({super.key});

  static const emojis = <String>[
    '😀',
    '😂',
    '😎',
    '😡',
    '😭',
    '👑',
    '💣',
    '🎲',
    '👍',
    '🌵',
    '🤔',
    '😮',
    '❤️',
    '😘',
    '💋',
    '🔪',
    '🎉',
    '🥳',
    '😴',
    '👏',
  ];

  static Future<String?> show(BuildContext context) => showDialog<String>(
        context: context,
        builder: (context) => const EmojiPickerDialog(),
      );

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: Container(
        constraints:
            BoxConstraints(maxWidth: 560, maxHeight: screenHeight * .76),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF073C91), Color(0xFF071D59), Color(0xFF101642)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFFD45A), width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 28, spreadRadius: 3),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 220,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5B24), Color(0xFFD80D20)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFFB55A), width: 2),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 8,
                      offset: Offset(0, 4)),
                ],
              ),
              child: Text(
                'Emoji',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: 4),
                itemCount: emojis.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: .86,
                ),
                itemBuilder: (context, index) => _EmojiTile(
                  emoji: emojis[index],
                  onTap: () => Navigator.of(context).pop(emojis[index]),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'CLOSE',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF074A9C), Color(0xFF061D4D)],
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFFFD45A), width: 1.7),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black38, blurRadius: 5, offset: Offset(0, 3)),
              ],
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 37)),
            ),
          ),
        ),
      );
}
