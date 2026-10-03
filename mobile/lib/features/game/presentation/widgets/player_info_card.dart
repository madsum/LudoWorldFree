import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/player_model.dart';

class PlayerInfoCard extends StatelessWidget {
  final PlayerModel player;
  final bool isCurrentTurn;

  const PlayerInfoCard({
    super.key,
    required this.player,
    required this.isCurrentTurn,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentTurn ? AppColors.gold : player.color.color,
          width: isCurrentTurn ? 2.5 : 1.5,
        ),
        boxShadow: [
          if (isCurrentTurn)
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Player Color Dot / Bot Icon
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: player.color.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.name,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Home: ${player.finishedPawnsCount}/4',
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
