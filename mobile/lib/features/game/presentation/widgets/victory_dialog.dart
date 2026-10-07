import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_assets.dart';
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
    final panelHeight =
        math.min(MediaQuery.sizeOf(context).height * 0.52, 640.0).toDouble();
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
          Positioned(
            left: 12,
            right: 12,
            bottom: 8,
            child: SafeArea(
              top: false,
              child: Center(
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold, width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x88F4C542), blurRadius: 8),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      AppAssets.logoJpeg,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.casino, color: AppColors.gold),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'LUDO WORLD FREE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cinzel(
                      color: AppColors.gold,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              'Best emerging game on Google Play',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
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
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
                ),
              ),
            ),
            const SizedBox(height: 4),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  humanWon ? 'Winner' : '1st place',
                  style: GoogleFonts.poppins(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
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
            const SizedBox(height: 2),
            _rankingRows(rankedPlayers),
            const SizedBox(height: 5),
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
                      padding: const EdgeInsets.symmetric(vertical: 8),
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
                      padding: const EdgeInsets.symmetric(vertical: 8),
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

  Widget _rankingRows(List<PlayerModel> players) {
    if (players.isEmpty) return const SizedBox.shrink();

    final remainingPlayers = players.skip(1).toList(growable: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rankingRow(players.first),
        if (remainingPlayers.isNotEmpty) ...[
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < remainingPlayers.length; index++) ...[
                if (index > 0) const SizedBox(width: 4),
                Expanded(
                  child: _compactRankingCell(
                    remainingPlayers[index],
                    index + 2,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _rankingRow(PlayerModel player) {
    final capturedCount = _capturedPawnCount(player);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC928),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE98A)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFF7B4800),
                  size: 18,
                ),
                const SizedBox(width: 1),
                Text(
                  '#1',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF7B4800),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
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
                color: const Color(0xFF402700),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _captureCountBadge(
            player,
            capturedCount,
            foregroundColor: const Color(0xFF402700),
          ),
        ],
      ),
    );
  }

  Widget _compactRankingCell(PlayerModel player, int placement) {
    final capturedCount = _capturedPawnCount(player);
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 4, 5),
      decoration: BoxDecoration(
        color: const Color(0xCC061A3A),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '#$placement',
                style: GoogleFonts.poppins(
                  color: AppColors.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 3),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: player.color.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 0.6),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          _captureCountBadge(
            player,
            capturedCount,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _captureCountBadge(
    PlayerModel player,
    int count, {
    required Color foregroundColor,
  }) {
    return Semantics(
      label: '$count pawns captured by ${player.name}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LudoPawnIcon(color: player.color, size: 13),
          const SizedBox(width: 2),
          const Icon(Icons.close_rounded, color: Color(0xFFFF655F), size: 11),
          const SizedBox(width: 2),
          Text(
            '$count captured',
            style: TextStyle(
              color: foregroundColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  int _capturedPawnCount(PlayerModel player) => player.killCounts.values.fold(
        0,
        (total, count) => total + count,
      );
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
