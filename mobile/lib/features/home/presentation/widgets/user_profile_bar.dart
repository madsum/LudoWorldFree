import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';

class UserProfileBar extends StatelessWidget {
  final String playerName;
  final String? avatarUrl;
  final String country;
  final String countryFlag;
  final int diamonds;
  final int coins;
  final VoidCallback? onSettingsPressed;
  final VoidCallback? onProfilePressed;

  const UserProfileBar({
    super.key,
    required this.playerName,
    this.avatarUrl,
    this.country = 'Netherlands',
    this.countryFlag = '🇳🇱',
    this.diamonds = 50,
    this.coins = 2350,
    this.onSettingsPressed,
    this.onProfilePressed,
  });

  IconData _getAvatarIcon(String? avatar) {
    switch (avatar) {
      case 'avatar_queen':
        return Icons.face_3_rounded;
      case 'avatar_wizard':
        return Icons.auto_awesome_rounded;
      case 'avatar_lion':
        return Icons.pets_rounded;
      case 'avatar_bot':
        return Icons.smart_toy_rounded;
      case 'avatar_warrior':
        return Icons.shield_rounded;
      case 'avatar_target':
        return Icons.sports_esports_rounded;
      case 'avatar_diamond':
        return Icons.diamond_rounded;
      case 'avatar_dice':
        return Icons.casino_rounded;
      case 'avatar_space':
        return Icons.rocket_launch_rounded;
      case 'avatar_ninja':
        return Icons.bolt_rounded;
      case 'avatar_dragon':
        return Icons.whatshot_rounded;
      case 'avatar_tiger':
        return Icons.cruelty_free_rounded;
      case 'avatar_star':
        return Icons.star_rounded;
      case 'avatar_trophy':
        return Icons.emoji_events_rounded;
      case 'avatar_gamer_boy':
        return Icons.headset_mic_rounded;
      case 'avatar_agent':
        return Icons.dark_mode_rounded;
      case 'avatar_mystic':
        return Icons.blur_on_rounded;
      case 'avatar_crown':
      default:
        return Icons.workspace_premium_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNetworkAvatar = avatarUrl != null && avatarUrl!.startsWith('http');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgNavy.withValues(alpha: 0.95),
        border: const Border(
          bottom: BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Avatar & Player Name
            GestureDetector(
              onTap: onProfilePressed,
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppColors.royalBlue, AppColors.gold],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: AppColors.gold, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: isNetworkAvatar
                          ? Image.network(
                              avatarUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Center(
                                child: Icon(
                                  _getAvatarIcon(avatarUrl),
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                _getAvatarIcon(avatarUrl),
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            countryFlag,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            playerName,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            country,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.white60,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Diamonds & Coins Counter
            Row(
              children: [
                // Diamond Badge
                _CurrencyPill(
                  icon: Icons.diamond_rounded,
                  iconColor: AppColors.diamondBlue,
                  value: '$diamonds',
                ),
                const SizedBox(width: 6),

                // Coin Badge
                _CurrencyPill(
                  icon: Icons.monetization_on_rounded,
                  iconColor: AppColors.coinGold,
                  value: '$coins',
                ),
                const SizedBox(width: 6),

                // Settings Button
                IconButton(
                  icon: const Icon(Icons.settings_rounded, color: Colors.white70, size: 24),
                  onPressed: onSettingsPressed,
                  tooltip: 'Settings',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;

  const _CurrencyPill({
    required this.icon,
    required this.iconColor,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
