import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/game_state.dart';

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
        ? gameState.players.firstWhere((p) => p.id == gameState.winnerIds.first).name
        : 'Winner';

    return AlertDialog(
      backgroundColor: AppColors.bgNavy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.gold, width: 2.5),
      ),
      title: Column(
        children: [
          const Icon(Icons.emoji_events_rounded, color: AppColors.gold, size: 54),
          const SizedBox(height: 8),
          Text(
            'VICTORY!',
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
          Text(
            '$winnerName WON THE MATCH!',
            style: GoogleFonts.poppins(
              fontSize: 16,
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
          ...gameState.players.map((player) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
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
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    '${player.finishedPawnsCount}/4 Home',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.white70,
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
            style: GoogleFonts.poppins(color: Colors.white60, fontWeight: FontWeight.bold),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black87,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onPlayAgain,
          child: Text(
            'PLAY AGAIN',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
