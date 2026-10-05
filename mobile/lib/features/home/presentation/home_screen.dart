import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../auth/presentation/widgets/guest_setup_dialog.dart';
import '../../game/presentation/controllers/game_controller.dart';
import '../../game/presentation/widgets/mode_config_dialog.dart';
import 'widgets/lobby_bottom_nav.dart';
import 'widgets/lobby_center_graphic.dart';
import 'widgets/lobby_game_card.dart';
import 'widgets/lobby_header_bar.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentNavIndex = 0;

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

  void _launchGameMode(BuildContext context,
      {required bool isVsComputer, required String title}) {
    final user = ref.read(authControllerProvider).user;
    final playerName = user?.name ?? 'Player 1';
    final avatarUrl = user?.avatarUrl;

    ModeConfigDialog.show(
      context,
      title: title,
      isVsComputer: isVsComputer,
      playerName: playerName,
      avatarUrl: avatarUrl,
      country: user?.country ?? 'Local Player',
      countryFlag: user?.countryFlag ?? '🌐',
      coins: user?.coins ?? 0,
      diamonds: user?.diamonds ?? 0,
      onStartGame: (players) {
        ref
            .read(gameControllerProvider.notifier)
            .startNewGame(players: players);
        context.push('/game');
      },
    );
  }

  void _showProfileInfoDialog(BuildContext context) {
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
                    const Icon(Icons.monetization_on_rounded,
                        color: AppColors.coinGold, size: 28),
                    const SizedBox(height: 4),
                    Text('${user.coins} Coins',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ],
                ),
                Column(
                  children: [
                    const Icon(Icons.diamond_rounded,
                        color: AppColors.diamondBlue, size: 28),
                    const SizedBox(height: 4),
                    Text('${user.diamonds} Diamonds',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
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
              style: GoogleFonts.poppins(
                  color: AppColors.gold, fontWeight: FontWeight.bold),
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

  void _showSettingsDialog(BuildContext context) {
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
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;
    final playerName = user?.name ?? 'Guest Player';
    final avatarUrl = user?.avatarUrl;
    final countryFlag = user?.countryFlag ?? '🇳🇱';
    final diamonds = user?.diamonds ?? 150;
    final coins = user?.coins ?? 50;

    final mediaQuery = MediaQuery.sizeOf(context);
    final isTablet = mediaQuery.width >= 650;

    return Scaffold(
      backgroundColor: const Color(0xFF07122E),
      body: Column(
        children: [
          // Top Header Bar
          LobbyHeaderBar(
            playerName: playerName,
            avatarUrl: avatarUrl,
            countryFlag: countryFlag,
            diamonds: diamonds,
            coins: coins,
            level: 3,
            onProfilePressed: () => _showProfileInfoDialog(context),
            onSettingsPressed: () => _showSettingsDialog(context),
            onInboxPressed: () =>
                _showComingSoonSnackBar(context, 'Mailbox Inbox'),
            onShopPressed: () =>
                _showComingSoonSnackBar(context, 'Coin & Diamond Store'),
          ),

          // Main Lobby Content Area
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isTablet ? 600 : double.infinity,
                  ),
                  child: Column(
                    children: [
                      // Top Logo & Centerpiece Graphic
                      const LobbyCenterGraphic(),

                      const SizedBox(height: 12),

                      // Row 1: 3 Vibrant Gold Game Cards (ONLINE, TEAM UP, FRIENDS)
                      Row(
                        children: [
                          Expanded(
                            child: LobbyGameCard(
                              title: 'ONLINE',
                              playerCount: '218,675',
                              cardType: LobbyCardType.online,
                              onTap: () => _showComingSoonSnackBar(
                                  context, 'Online Multiplayer'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: LobbyGameCard(
                              title: 'TEAM UP',
                              playerCount: '4,144',
                              cardType: LobbyCardType.teamUp,
                              onTap: () => _showComingSoonSnackBar(
                                  context, 'Team Up 2v2'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: LobbyGameCard(
                              title: 'FRIENDS',
                              playerCount: '16,393',
                              cardType: LobbyCardType.friends,
                              onTap: () => _showComingSoonSnackBar(
                                  context, 'Play with Friends'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Row 2: 2 Vibrant Gold Game Cards (COMPUTER & PASS N PLAY)
                      Row(
                        children: [
                          Expanded(
                            child: LobbyGameCard(
                              title: 'COMPUTER',
                              cardType: LobbyCardType.computer,
                              onTap: () => _launchGameMode(context,
                                  isVsComputer: true, title: 'Vs Computer'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LobbyGameCard(
                              title: 'PASS N PLAY',
                              cardType: LobbyCardType.passNPlay,
                              onTap: () => _launchGameMode(context,
                                  isVsComputer: false, title: 'Pass & Play'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom Navigation Bar (HOME, LIVE CHAT, SOCIAL)
          LobbyBottomNav(
            selectedIndex: _currentNavIndex,
            onTap: (index) {
              setState(() => _currentNavIndex = index);
              if (index != 0) {
                _showComingSoonSnackBar(
                    context, index == 1 ? 'Live Voice Chat' : 'Social Hub');
              }
            },
          ),
        ],
      ),
    );
  }
}
