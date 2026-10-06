import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/player_model.dart';
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
    final winner = gameState.players.firstWhere(
      (player) => gameState.winnerIds.contains(player.id),
      orElse: () => gameState.players.first,
    );
    final humanPlayer = gameState.players.firstWhere(
      (player) => !player.isBot,
      orElse: () => gameState.players.first,
    );
    final humanWon = winner.id == humanPlayer.id;
    final rankedPlayers = gameState.players.toList()
      ..sort((a, b) {
        final aGroup = a.isEliminated ? 2 : (a.rank > 0 ? 0 : 1);
        final bGroup = b.isEliminated ? 2 : (b.rank > 0 ? 0 : 1);
        if (aGroup != bGroup) return aGroup.compareTo(bGroup);
        if (aGroup == 2) {
          final eliminationOrder =
              b.eliminationOrder.compareTo(a.eliminationOrder);
          if (eliminationOrder != 0) return eliminationOrder;
        }
        final rankOrder = a.rank.compareTo(b.rank);
        return rankOrder != 0 ? rankOrder : a.name.compareTo(b.name);
      });

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: _GoldenGlitter()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final panelHeight = math
                    .min(
                      constraints.maxHeight * 0.74,
                      640.0,
                    )
                    .toDouble();
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: SizedBox(
                        width: double.infinity,
                        height: panelHeight,
                        child: _buildResultsPanel(
                          winner: winner,
                          humanWon: humanWon,
                          rankedPlayers: rankedPlayers,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel({
    required PlayerModel winner,
    required bool humanWon,
    required List<PlayerModel> rankedPlayers,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1457B8), Color(0xFF092653), Color(0xFF07172F)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 24, spreadRadius: 2),
          BoxShadow(color: Color(0x66F4C542), blurRadius: 16),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.stars_rounded,
                    color: AppColors.gold, size: 28),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'LUDO WORLD FREE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cinzel(
                      color: AppColors.gold,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Best emerging game on Google Play',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0877E8), Color(0xFF063C91)],
                ),
                border: Border.all(color: const Color(0xFFFFD85B), width: 1.5),
              ),
              child: Text(
                humanWon ? 'CONGRATULATIONS!' : 'MATCH COMPLETE',
                textAlign: TextAlign.center,
                style: GoogleFonts.cinzel(
                  color: AppColors.gold,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(Icons.emoji_events, color: AppColors.gold, size: 23),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    winner.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  humanWon ? 'Winner' : '1st place',
                  style: GoogleFonts.poppins(
                    color: AppColors.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Divider(color: Colors.white.withValues(alpha: 0.3))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'MATCH RANKINGS',
                    style: GoogleFonts.poppins(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                Expanded(
                    child: Divider(color: Colors.white.withValues(alpha: 0.3))),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < rankedPlayers.length; index++)
                      _rankingRow(rankedPlayers[index], index + 1),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onExitToLobby,
                    icon: const Icon(Icons.home_rounded, size: 19),
                    label: const Text('LOBBY'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      textStyle: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onPlayAgain,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('PLAY AGAIN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF48D12D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(
                            color: Color(0xFFB8FF65), width: 1.5),
                      ),
                      textStyle: GoogleFonts.poppins(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankingRow(PlayerModel player, int placement) {
    final capturedPawns = player.killCounts.entries
        .where((entry) => entry.value > 0)
        .toList(growable: false);
    final capturedLabel = capturedPawns.isEmpty
        ? 'No pawns captured'
        : capturedPawns
            .map((entry) =>
                '${entry.value} ${entry.key.displayName.toLowerCase()} pawns captured')
            .join(', ');
    final isWinner = placement == 1;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: isWinner ? const Color(0xFFFFC928) : const Color(0xCC061A3A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isWinner ? const Color(0xFFFFE98A) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Icon(
              isWinner ? Icons.workspace_premium_rounded : Icons.military_tech,
              color: isWinner ? const Color(0xFF7B4800) : Colors.white70,
              size: 22,
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: player.color.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 0.7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: isWinner ? const Color(0xFF402700) : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            label: capturedLabel,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: capturedPawns.isEmpty
                  ? [
                      Text(
                        '0 captures',
                        style: TextStyle(
                          color: isWinner ? Colors.black54 : Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ]
                  : [
                      for (final entry in capturedPawns) ...[
                        LudoPawnIcon(color: entry.key, size: 14),
                        const SizedBox(width: 2),
                        const Icon(Icons.close_rounded,
                            color: Color(0xFFFF655F), size: 12),
                        const SizedBox(width: 2),
                        Text(
                          '${entry.value}',
                          style: TextStyle(
                            color: isWinner ? Colors.black87 : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (entry != capturedPawns.last)
                          const SizedBox(width: 5),
                      ],
                    ],
            ),
          ),
        ],
      ),
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

  final List<_Particle> _particles = List.generate(
    45,
    (index) => _Particle(
      x: (index * 37 % 100) / 100,
      y: (index * 61 % 100) / 100,
      size: 1.4 + (index % 4) * 0.8,
      phase: (index % 12) / 12,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _GlitterPainter(_particles, _controller.value),
          size: Size.infinite,
        ),
      );
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final double phase;

  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
  });
}

class _GlitterPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  const _GlitterPainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final particle in particles) {
      final twinkle =
          (math.sin((progress + particle.phase) * math.pi * 2) + 1) / 2;
      paint.color = AppColors.gold.withValues(alpha: 0.12 + twinkle * 0.45);
      final y = (particle.y + progress * 0.08) % 1;
      canvas.drawCircle(
        Offset(particle.x * size.width, y * size.height),
        particle.size * (0.7 + twinkle * 0.6),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlitterPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
