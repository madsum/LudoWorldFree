import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../auth/presentation/widgets/guest_setup_dialog.dart';
import 'widgets/menu_card.dart';
import 'widgets/user_profile_bar.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const List<MenuCardData> _menuCards = [
    MenuCardData(
      title: 'Online Multiplayer',
      subtitle: 'Play live with players worldwide',
      icon: Icons.public_rounded,
      gradientColors: [AppColors.royalBlue, Color(0xFF1E3A8A)],
    ),
    MenuCardData(
      title: 'Team Up 2v2',
      subtitle: 'Join forces with a teammate',
      icon: Icons.groups_rounded,
      gradientColors: [Color(0xFF8B5CF6), Color(0xFF5B21B6)],
    ),
    MenuCardData(
      title: 'Play with Friends',
      subtitle: 'Create room & invite friends',
      icon: Icons.diversity_3_rounded,
      gradientColors: [Color(0xFFEC4899), Color(0xFF9D174D)],
    ),
    MenuCardData(
      title: 'Vs Computer',
      subtitle: 'Offline practice vs smart AI',
      icon: Icons.smart_toy_rounded,
      gradientColors: [AppColors.green, Color(0xFF15803D)],
    ),
    MenuCardData(
      title: 'Pass & Play',
      subtitle: 'Local play on same device',
      icon: Icons.phone_android_rounded,
      gradientColors: [Color(0xFFF97316), Color(0xFFC2410C)],
    ),
    MenuCardData(
      title: 'Tournament',
      subtitle: 'Compete for mega coin rewards',
      icon: Icons.emoji_events_rounded,
      gradientColors: [AppColors.gold, Color(0xFFB45309)],
    ),
  ];

  void _showComingSoonSnackBar(BuildContext context, String modeName) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.bgNavy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$modeName mode is coming in Part 2!',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showProfileInfoDialog(BuildContext context, WidgetRef ref) {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgNavy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.gold, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.person_pin_rounded, color: AppColors.gold),
            const SizedBox(width: 10),
            Text(
              'PLAYER PROFILE',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(user.countryFlag, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.name,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Country: ${user.country}',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
            ),
            if (user.email != null && user.email!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Email: ${user.email}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.white54),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 28),
                    const SizedBox(height: 4),
                    Text('${user.coins} Coins', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                Column(
                  children: [
                    const Icon(Icons.diamond_rounded, color: AppColors.diamondBlue, size: 28),
                    const SizedBox(height: 4),
                    Text('${user.diamonds} Diamonds', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              GuestSetupDialog.showEditProfile(
                context,
                currentName: user.name,
                currentAvatarUrl: user.avatarUrl,
                currentCountry: user.country,
                currentCountryFlag: user.countryFlag,
              );
            },
            child: Text(
              'EDIT PROFILE',
              style: GoogleFonts.poppins(color: AppColors.gold, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgNavy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.settings_rounded, color: AppColors.gold),
            const SizedBox(width: 10),
            Text(
              'Settings',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppConstants.appName} v${AppConstants.appVersion}',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Developed by ${AppConstants.publisher}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout_rounded, color: AppColors.red),
              title: Text(
                'Sign Out',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: AppColors.red,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authControllerProvider.notifier).signOut();
                if (context.mounted) {
                  context.go('/login');
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(color: AppColors.gold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;
    final playerName = user?.name ?? 'Guest Player';
    final avatarUrl = user?.avatarUrl;
    final country = user?.country ?? 'Netherlands';
    final countryFlag = user?.countryFlag ?? '🇳🇱';
    final diamonds = user?.diamonds ?? 50;
    final coins = user?.coins ?? 2350;

    final mediaQuery = MediaQuery.sizeOf(context);
    final isTablet = mediaQuery.width >= 650;
    final crossAxisCount = isTablet ? 3 : 2;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // Top User Profile Bar
          UserProfileBar(
            playerName: playerName,
            avatarUrl: avatarUrl,
            country: country,
            countryFlag: countryFlag,
            diamonds: diamonds,
            coins: coins,
            onProfilePressed: () => _showProfileInfoDialog(context, ref),
            onSettingsPressed: () => _showSettingsDialog(context, ref),
          ),

          // Main Game Modes Grid
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Banner Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.bgNavy, AppColors.bgCard],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.5), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.15),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'WELCOME TO LUDO WORLD FREE!',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.gold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Select a game mode below to start playing. All modes are 100% free!',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.sports_esports_rounded,
                          size: 42,
                          color: AppColors.gold,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Menu Section Label
                  Text(
                    'SELECT GAME MODE',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white70,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Grid of 6 Menu Cards
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _menuCards.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: isTablet ? 1.35 : 1.15,
                    ),
                    itemBuilder: (context, index) {
                      final cardData = _menuCards[index];
                      return MenuCard(
                        data: cardData,
                        onTap: () => _showComingSoonSnackBar(context, cardData.title),
                      );
                    },
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
