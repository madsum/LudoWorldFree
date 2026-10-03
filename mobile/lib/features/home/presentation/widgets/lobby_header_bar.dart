import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';

class LobbyHeaderBar extends StatelessWidget {
  final String playerName;
  final String? avatarUrl;
  final String countryFlag;
  final int diamonds;
  final int coins;
  final int level;
  final VoidCallback onProfilePressed;
  final VoidCallback onSettingsPressed;
  final VoidCallback onInboxPressed;
  final VoidCallback onShopPressed;

  const LobbyHeaderBar({
    super.key,
    required this.playerName,
    this.avatarUrl,
    required this.countryFlag,
    required this.diamonds,
    required this.coins,
    this.level = 3,
    required this.onProfilePressed,
    required this.onSettingsPressed,
    required this.onInboxPressed,
    required this.onShopPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isAssetAvatar = avatarUrl != null && (avatarUrl!.startsWith('assets/') || avatarUrl!.endsWith('.webp'));
    final isNetworkAvatar = avatarUrl != null && avatarUrl!.startsWith('http');

    Widget avatarImage;
    if (isAssetAvatar) {
      avatarImage = Image.asset(avatarUrl!, fit: BoxFit.cover);
    } else if (isNetworkAvatar) {
      avatarImage = Image.network(avatarUrl!, fit: BoxFit.cover);
    } else {
      avatarImage = const Icon(Icons.person_rounded, color: Colors.white, size: 22);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B3E),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFFFD700), width: 1.8),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left Group: Profile Avatar with Level Star + Settings + Mail
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onProfilePressed,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFEA00), Color(0xFFFF8F00)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 19,
                          backgroundColor: AppColors.bgCard,
                          child: ClipOval(child: avatarImage),
                        ),
                      ),
                      // Level Star Badge
                      Positioned(
                        left: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFF8F00)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 1),
                            boxShadow: const [
                              BoxShadow(color: Colors.black45, blurRadius: 4),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.white, size: 10),
                              Text(
                                '$level',
                                style: GoogleFonts.poppins(
                                  fontSize: 9.5,
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
                ),

                const SizedBox(width: 8),

                // Settings Gear Button
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 22),
                  onPressed: onSettingsPressed,
                ),

                const SizedBox(width: 6),

                // Mail Inbox Button with Badge "1"
                Stack(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.mark_as_unread_rounded, color: Color(0xFFFFD700), size: 22),
                      onPressed: onInboxPressed,
                    ),
                    Positioned(
                      right: -1,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          '1',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Right Group: Diamond Counter, Coin Counter, Shop Button
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Diamond Counter Pill
                  Flexible(
                    child: _LobbyCurrencyPill(
                      icon: Icons.diamond_rounded,
                      iconColor: const Color(0xFF00E5FF),
                      value: '$diamonds',
                      onAdd: onShopPressed,
                    ),
                  ),

                  const SizedBox(width: 5),

                  // Coin Counter Pill
                  Flexible(
                    child: _LobbyCurrencyPill(
                      icon: Icons.monetization_on_rounded,
                      iconColor: const Color(0xFFFFD700),
                      value: '$coins',
                      onAdd: onShopPressed,
                    ),
                  ),

                  const SizedBox(width: 5),

                  // Shopping Cart Button
                  GestureDetector(
                    onTap: onShopPressed,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFEA00), Color(0xFFFF8F00)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 4),
                        ],
                      ),
                      child: const Icon(Icons.shopping_cart_rounded, color: Colors.black87, size: 17),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LobbyCurrencyPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final VoidCallback onAdd;

  const _LobbyCurrencyPill({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.only(left: 4, right: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF070F26),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF1E3A8A), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 15),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Color(0xFF00E676),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 12),
            ),
          ),
        ],
      ),
    );
  }
}
