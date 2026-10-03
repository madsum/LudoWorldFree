import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum LobbyCardType {
  online,
  teamUp,
  friends,
  computer,
  passNPlay,
}

class LobbyGameCard extends StatelessWidget {
  final String title;
  final String? playerCount;
  final LobbyCardType cardType;
  final VoidCallback onTap;

  const LobbyGameCard({
    super.key,
    required this.title,
    this.playerCount,
    required this.cardType,
    required this.onTap,
  });

  Widget _buildCardTopGraphic() {
    switch (cardType) {
      case LobbyCardType.online:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_android_rounded, color: Color(0xFFFFD700), size: 18),
            const SizedBox(width: 2),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xFF00E5FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.public_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.phone_android_rounded, color: Color(0xFFFFD700), size: 18),
          ],
        );
      case LobbyCardType.teamUp:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_rounded, color: Color(0xFF00E5FF), size: 16),
            const SizedBox(width: 2),
            const Icon(Icons.gavel_rounded, color: Color(0xFFFFD700), size: 24), // Sword
            const SizedBox(width: 2),
            const Icon(Icons.location_on_rounded, color: Color(0xFFFF1744), size: 16),
          ],
        );
      case LobbyCardType.friends:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_android_rounded, color: Color(0xFFFFD700), size: 18),
            const SizedBox(width: 2),
            const Icon(Icons.favorite_rounded, color: Color(0xFFFF1744), size: 24),
            const SizedBox(width: 2),
            const Icon(Icons.phone_android_rounded, color: Color(0xFFFFD700), size: 18),
          ],
        );
      case LobbyCardType.computer:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEA00),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black26, width: 1.5),
          ),
          child: Text(
            'VS',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
        );
      case LobbyCardType.passNPlay:
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_rounded, color: Color(0xFFFFD700), size: 22),
            Icon(Icons.square_rounded, color: Colors.white, size: 18),
            Icon(Icons.person_rounded, color: Color(0xFFFFD700), size: 22),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF59D),
            Color(0xFFFFE082),
            Color(0xFFFFCA28),
            Color(0xFFFFB300),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF), width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF00838F),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Graphic
                _buildCardTopGraphic(),

                const SizedBox(height: 6),

                // Main Title Text
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.8,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2)),
                        Shadow(color: Color(0xFF1565C0), blurRadius: 2, offset: Offset(0, 1)),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Live Player Count Badge
                if (playerCount != null) ...[
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Players: $playerCount',
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0D1B3E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
