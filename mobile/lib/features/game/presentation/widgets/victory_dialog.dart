import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/game_state.dart';
import 'ludo_pawn_icon.dart';

class VictoryDialog extends StatelessWidget {
  final GameState gameState;
  final VoidCallback onPlayAgain;
  final VoidCallback onExitToLobby;

  const VictoryDialog({
    super.key,
    required this.gameState,
    required this.onPlayAgain,
    required this.onExitToLobby,
  });

  @override
  Widget build(BuildContext context) {
    final winnerName = gameState.winnerIds.isNotEmpty
        ? gameState.players
            .firstWhere((p) => p.id == gameState.winnerIds.first)
            .name
        : 'Winner';
    final humanPlayer = gameState.players.firstWhere(
      (player) => !player.isBot,
      orElse: () => gameState.players.first,
    );
    final humanWon = gameState.winnerIds.contains(humanPlayer.id);
    final rankedPlayers = gameState.players.toList()
      ..sort((a, b) {
        final aGroup = a.isEliminated ? 2 : (a.rank > 0 ? 0 : 1);
        final bGroup = b.isEliminated ? 2 : (b.rank > 0 ? 0 : 1);
        if (aGroup != bGroup) {
          return aGroup.compareTo(bGroup);
        }
        if (aGroup == 2) {
          final eliminationOrder =
              b.eliminationOrder.compareTo(a.eliminationOrder);
          if (eliminationOrder != 0) return eliminationOrder;
        }
        final rankOrder = a.rank.compareTo(b.rank);
        return rankOrder != 0 ? rankOrder : a.name.compareTo(b.name);
      });

    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(child: _GoldenGlitter()),
        Center(
          child: AlertDialog(
            backgroundColor: AppColors.bgNavy,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.gold, width: 2.5),
            ),
            title: Column(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.72, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) => Transform.scale(
                    scale: scale,
                    child: child,
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: AppColors.gold,
                    size: 68,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'WINNER!',
                  style: GoogleFonts.cinzel(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 850),
                  curve: Curves.easeOutBack,
                  builder: (context, progress, child) => Opacity(
                    opacity: progress.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, (1 - progress) * 18),
                      child: Transform.scale(
                        scale: 0.86 + progress * 0.14,
                        child: child,
                      ),
                    ),
                  ),
                  child: Text(
                    winnerName.toUpperCase(),
                    style: GoogleFonts.cinzel(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      color: AppColors.gold,
                      letterSpacing: 1.4,
                      shadows: const [
                        Shadow(color: AppColors.gold, blurRadius: 14),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  humanWon
                      ? 'You won the match!'
                      : '$winnerName won the match.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                Text(
                  'MATCH RANKINGS',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(rankedPlayers.length, (index) {
                  final player = rankedPlayers[index];
                  final placement = index + 1;
                  final killCount = player.killCounts.values.fold<int>(
                    0,
                    (total, count) => total + count,
                  );

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '#$placement',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: placement == 1
                                  ? AppColors.gold
                                  : Colors.white60,
                            ),
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: player.color.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            player.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          label: '$killCount pawns captured',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LudoPawnIcon(color: player.color, size: 14),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.close_rounded,
                                color: Color(0xFFFF655F),
                                size: 13,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '$killCount',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceAround,
            actions: [
              TextButton(
                onPressed: onExitToLobby,
                child: Text(
                  'LOBBY',
                  style: GoogleFonts.poppins(
                      color: Colors.white60, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onPlayAgain,
                child: Text(
                  'PLAY AGAIN',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoldenGlitter extends StatefulWidget {
  const _GoldenGlitter();

  @override
  State<_GoldenGlitter> createState() => _GoldenGlitterState();
}

class _GoldenGlitterState extends State<_GoldenGlitter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _GoldenGlitterPainter(_controller.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GoldenGlitterPainter extends CustomPainter {
  final double progress;

  const _GoldenGlitterPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const count = 52;
    for (var i = 0; i < count; i++) {
      final seed = (i * 0.61803398875) % 1;
      final fall = (progress + seed) % 1;
      final drift = math.sin((fall * 2 + seed) * math.pi * 2) * 13;
      final x = seed * size.width + drift;
      final y = fall * size.height;
      final radius = 1.5 + (i % 4) * 0.75;
      final opacity = (math.sin(fall * math.pi) * 0.9).clamp(0.0, 0.9);
      final paint = Paint()
        ..color = (i % 3 == 0 ? Colors.white : AppColors.gold)
            .withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
      if (i % 5 == 0) {
        final vertical = Paint()
          ..color = AppColors.gold.withValues(alpha: opacity * 0.72)
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(x, y - radius * 1.8),
          Offset(x, y + radius * 1.8),
          vertical,
        );
        canvas.drawLine(
          Offset(x - radius * 1.8, y),
          Offset(x + radius * 1.8, y),
          vertical,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GoldenGlitterPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
