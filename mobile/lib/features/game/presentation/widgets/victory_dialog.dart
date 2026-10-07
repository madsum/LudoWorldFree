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

    final rankedPlayers = gameState.players.toList()
      ..sort((a, b) {
        final aGroup = a.isEliminated ? 2 : (a.rank > 0 ? 0 : 1);
        final bGroup = b.isEliminated ? 2 : (b.rank > 0 ? 0 : 1);
        if (aGroup != bGroup) return aGroup.compareTo(bGroup);
        if (aGroup == 2) {
          final eliminationOrder = b.eliminationOrder.compareTo(a.eliminationOrder);
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
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _buildResultsScrollPanel(
                  context,
                  winner: winner,
                  rankedPlayers: rankedPlayers,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsScrollPanel(
    BuildContext context, {
    required PlayerModel winner,
    required List<PlayerModel> rankedPlayers,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top 3D Crown & Game Name Header
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold, width: 2),
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
            const SizedBox(width: 8),
            Text(
              'LUDO WORLD FREE',
              style: GoogleFonts.cinzel(
                color: AppColors.gold,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                shadows: const [Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 2))],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Best emerging game on Google Play',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),

        const SizedBox(height: 10),

        // Golden 3D Scroll Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFEA00), Color(0xFFFF8F00), Color(0xFFFFEA00)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            'Congratulations! ${winner.name}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              shadows: const [Shadow(color: Colors.white, blurRadius: 3)],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Main Compact Results Box
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F3A8C), Color(0xFF0A2254), Color(0xFF05112B)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.gold, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Player Rankings List
              ...rankedPlayers.asMap().entries.map((entry) {
                final index = entry.key;
                final player = entry.value;
                final isWinner = index == 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isWinner ? const Color(0xFFFFC107) : const Color(0xFF132B5C),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isWinner ? const Color(0xFFFFF176) : Colors.white24,
                      width: isWinner ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          // Rank Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isWinner ? const Color(0xFF8D5300) : Colors.black38,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isWinner ? Icons.workspace_premium_rounded : Icons.star_rounded,
                                  color: isWinner ? AppColors.gold : Colors.white70,
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  isWinner ? '#1' : '#${index + 1}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isWinner ? AppColors.gold : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Player Avatar
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: player.color.color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.2),
                            ),
                            child: Center(
                              child: Text(
                                player.countryFlag,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Player Name
                          Expanded(
                            child: Text(
                              player.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isWinner ? Colors.black87 : Colors.white,
                              ),
                            ),
                          ),

                          // Reward / Status Tag
                          if (isWinner)
                            Row(
                              children: [
                                const Icon(Icons.monetization_on_rounded, color: Color(0xFF5D4037), size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  '+1,900',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF5D4037),
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              player.isEliminated ? 'Forfeit' : 'Lost',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white54,
                              ),
                            ),
                        ],
                      ),

                      // Pawn Kills Line: Opponent Killed Pawns by Color Symbol & Number
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            'Kills: ',
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: isWinner ? const Color(0xFF5D4037) : Colors.white70,
                            ),
                          ),
                          _buildPawnKillsRow(player, isWinner: isWinner),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 6),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 6),

              // Match Stats Badges Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatBadge(icon: Icons.emoji_events_rounded, iconColor: AppColors.gold, label: '+10'),
                  _StatBadge(icon: Icons.star_rounded, iconColor: Colors.amberAccent, label: '+60 XP'),
                  _StatBadge(icon: Icons.gavel_rounded, iconColor: Colors.redAccent, label: '+${_totalKills(winner)} Kills'),
                  _StatBadge(icon: Icons.thumb_up_rounded, iconColor: Colors.lightBlueAccent, label: '9'),
                  _StatBadge(icon: Icons.thumb_down_rounded, iconColor: Colors.orangeAccent, label: '0'),
                ],
              ),

              const SizedBox(height: 12),

              // Action Buttons Row (Back, Home, Share, Play Again)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CircleActionButton(
                    icon: Icons.arrow_back_rounded,
                    color: const Color(0xFF1E3A8A),
                    onTap: onExitToLobby,
                  ),
                  _CircleActionButton(
                    icon: Icons.home_rounded,
                    color: const Color(0xFF0288D1),
                    onTap: onExitToLobby,
                  ),
                  _CircleActionButton(
                    icon: Icons.share_rounded,
                    color: const Color(0xFFD97706),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Match results copied to clipboard!')),
                      );
                    },
                  ),

                  // Replay / Play Again Button
                  GestureDetector(
                    onTap: onPlayAgain,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E676), Color(0xFF2E7D32)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 1.8),
                        boxShadow: const [
                          BoxShadow(color: Color(0xFF00E676), blurRadius: 8, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            'REPLAY',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPawnKillsRow(PlayerModel player, {required bool isWinner}) {
    final opponentColors = gameState.players
        .map((p) => p.color)
        .where((color) => color != player.color)
        .toSet()
        .toList(growable: false);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < opponentColors.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LudoPawnIcon(color: opponentColors[index], size: 11),
              const SizedBox(width: 2),
              Text(
                '×${player.killCounts[opponentColors[index]] ?? 0}',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isWinner ? const Color(0xFF402700) : Colors.white,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  int _totalKills(PlayerModel player) {
    return player.killCounts.values.fold(0, (sum, count) => sum + count);
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _StatBadge({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 1),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CircleActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.8),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 5, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
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
