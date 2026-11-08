import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/ad_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/ads/ad_mob_consent_service.dart';
import '../../../core/ads/rewarded_ad_service.dart';
import '../../../shared/widgets/flying_coin_overlay.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/widgets/guest_setup_dialog.dart';
import '../../game/presentation/controllers/game_controller.dart';
import '../../game/presentation/widgets/exit_game_dialog.dart';
import '../../game/presentation/widgets/mode_config_dialog.dart';
import 'widgets/lobby_bottom_nav.dart';
import 'widgets/lobby_center_graphic.dart';
import 'widgets/lobby_game_card.dart';
import 'widgets/lobby_header_bar.dart';
import 'widgets/online_matchmaking_dialog.dart';
import 'widgets/daily_bonus_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final ProviderSubscription<AuthState> _authSubscription;
  Timer? _dailyBonusStartupTimer;
  Timer? _dailyBonusStartupPoll;
  int _currentNavIndex = 0;
  bool _isClaimingReward = false;
  bool _isClaimingDailyBonus = false;
  bool _dailyBonusDialogShowing = false;
  String? _dailyBonusPopupPlayerId;
  final GlobalKey _walletKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _waitForStartupUser();
    _authSubscription = ref.listenManual<AuthState>(
      authControllerProvider,
      _handleAuthStateChanged,
      fireImmediately: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userId = ref.read(authControllerProvider).user?.id;
      if (userId != null) _queueDailyBonusCheck(userId);
    });
    Future.microtask(() {
      ref.read(rewardedAdServiceProvider).preloadAd();
    });
  }

  void _handleAuthStateChanged(AuthState? previous, AuthState next) {
    final user = next.user;
    if (user == null) {
      _dailyBonusStartupTimer?.cancel();
      _dailyBonusPopupPlayerId = null;
      return;
    }
    _dailyBonusStartupPoll?.cancel();
    _dailyBonusStartupPoll = null;
    if (_dailyBonusPopupPlayerId == user.id) return;

    _dailyBonusPopupPlayerId = user.id;
    _queueDailyBonusCheck(user.id);
  }

  void _waitForStartupUser() {
    var attempts = 0;
    _dailyBonusStartupPoll = Timer.periodic(
      const Duration(milliseconds: 250),
      (timer) {
        final authState = ref.read(authControllerProvider);
        if (authState.user != null) {
          timer.cancel();
          _dailyBonusStartupPoll = null;
          _handleAuthStateChanged(null, authState);
          return;
        }
        if (++attempts >= 40) {
          timer.cancel();
          _dailyBonusStartupPoll = null;
        }
      },
    );
  }

  void _queueDailyBonusCheck(String userId) {
    _dailyBonusStartupTimer?.cancel();
    _dailyBonusStartupTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted ||
          _dailyBonusPopupPlayerId != userId ||
          ref.read(authControllerProvider).user?.id != userId) {
        return;
      }
      _loadDailyBonusStatus(userId);
    });
  }

  void _showComingSoonSnackBar(String modeName) {
    if (!mounted) return;
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

  Future<void> _loadDailyBonusStatus(String userId) async {
    final status =
        await ref.read(authControllerProvider.notifier).getDailyBonusStatus();
    if (!mounted ||
        _dailyBonusPopupPlayerId != userId ||
        ref.read(authControllerProvider).user?.id != userId) {
      return;
    }
    if (status == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.bgNavy,
          content: Text(
            'Daily bonus is unavailable. Check your connection and make sure the game backend is running.',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          action: SnackBarAction(
            label: 'RETRY',
            textColor: AppColors.gold,
            onPressed: () => _loadDailyBonusStatus(userId),
          ),
        ),
      );
      return;
    }
    final bonusStatus = status;
    if (bonusStatus.claimedToday || _dailyBonusDialogShowing) return;

    // The status response arrives after the first Home frame. Showing the
    // dialog directly avoids waiting for another frame, which may not be
    // scheduled while the app is idle on a physical device.
    _dailyBonusDialogShowing = true;
    showDialog<DailyBonusStatus>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => DailyBonusDialog(
        status: bonusStatus,
        onClaim: _watchAdAndClaimDailyBonus,
      ),
    ).then((result) async {
      _dailyBonusDialogShowing = false;
      if (mounted && result?.success == true) {
        await _flyCoinsFromBottomToWallet();
        await _showDailyBonusCongratulations(result!);
      } else if (mounted && result?.claimedToday == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.bgNavy,
            content: Text(
              'Today’s bonus was already credited. Your wallet has been refreshed.',
              style: GoogleFonts.poppins(color: AppColors.gold),
            ),
          ),
        );
      }
    });
  }

  Future<DailyBonusStatus?> _watchAdAndClaimDailyBonus() async {
    if (_isClaimingDailyBonus) return null;
    setState(() => _isClaimingDailyBonus = true);
    final resultCompleter = Completer<DailyBonusStatus?>();
    var earnedReward = false;
    var completed = false;
    void complete(DailyBonusStatus? result) {
      if (completed) return;
      completed = true;
      if (mounted) setState(() => _isClaimingDailyBonus = false);
      resultCompleter.complete(result);
    }

    await ref.read(rewardedAdServiceProvider).showRewardedAd(
      onRewardEarned: (amount, providerRewardId) {
        earnedReward = amount > 0 && providerRewardId.isNotEmpty;
      },
      onAdClosed: () {
        if (!earnedReward) {
          complete(null);
          return;
        }
        ref
            .read(authControllerProvider.notifier)
            .claimDailyBonus()
            .then(complete);
      },
      onError: (error) {
        complete(null);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.bgNavy,
          content:
              Text(error, style: GoogleFonts.poppins(color: AppColors.gold)),
        ));
      },
    );
    return resultCompleter.future;
  }

  Future<void> _showDailyBonusCongratulations(DailyBonusStatus result) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B3E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.gold, width: 2.5),
        ),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFFFEA00),
                    Color(0xFFFF8F00),
                    Color(0xFFB76E00)
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: Color(0xFFFF8F00), blurRadius: 14)
                ],
              ),
              child: const Icon(Icons.monetization_on_rounded,
                  color: Colors.white, size: 52),
            ),
            const SizedBox(height: 16),
            Text('CONGRATULATIONS!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: AppColors.gold,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                )),
            const SizedBox(height: 8),
            Text('You got your Day ${result.rewardDay} daily bonus!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 8),
            Text('+${result.rewardAmount} coins added to your wallet',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: AppColors.coinGold,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                )),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: const Color(0xFF07122E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('AWESOME',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
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

  void _watchAdAndEarnGold(BuildContext context) async {
    if (_isClaimingReward) return;
    final rewardedAdService = ref.read(rewardedAdServiceProvider);
    var earnedAmount = 0;
    var earnedProviderRewardId = '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.bgNavy,
        content: Text(
          'Loading Rewarded Video Ad...',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    await rewardedAdService.showRewardedAd(
      onRewardEarned: (amount, rewardId) {
        _isClaimingReward = true;
        earnedAmount = amount;
        earnedProviderRewardId = rewardId;
      },
      onAdClosed: () {
        if (earnedAmount <= 0 || earnedProviderRewardId.isEmpty) {
          _isClaimingReward = false;
          return;
        }
        unawaited(_finishWatchAdReward(
          context,
          earnedAmount,
          earnedProviderRewardId,
        ));
      },
      onError: (error) {
        _isClaimingReward = false;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.bgNavy,
              content: Text(error,
                  style: GoogleFonts.poppins(color: AppColors.gold)),
            ),
          );
        }
      },
    );
  }

  Future<void> _finishWatchAdReward(
    BuildContext context,
    int amount,
    String providerRewardId,
  ) async {
    final credited =
        await ref.read(authControllerProvider.notifier).addGoldReward(
              amount: amount,
              providerRewardId: providerRewardId,
            );
    if (!context.mounted) return;
    if (!credited) {
      _isClaimingReward = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.bgNavy,
          content: Text(
            'Your ad reward could not be added. Please try again.',
            style: GoogleFonts.poppins(color: AppColors.gold),
          ),
        ),
      );
      return;
    }

    await _flyCoinsFromBottomToWallet();
    _isClaimingReward = false;
    if (context.mounted) _showMiddleRewardDialog(context, amount);
  }

  Offset _getWidgetCenter(GlobalKey key, {required Offset fallback}) {
    final renderBox = key.currentContext?.findRenderObject();
    if (renderBox is RenderBox && renderBox.hasSize) {
      return renderBox.localToGlobal(renderBox.size.center(Offset.zero));
    }
    return fallback;
  }

  Future<void> _flyCoinsFromBottomToWallet() {
    if (!mounted) return Future<void>.value();

    final screenSize = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final animationComplete = Completer<void>();
    FlyingCoinOverlay.show(
      context,
      startOffset: Offset(
        screenSize.width / 2,
        screenSize.height - safeBottom - 28,
      ),
      endOffset: _getWidgetCenter(
        _walletKey,
        fallback: Offset(screenSize.width - 60, 32),
      ),
      onComplete: () => animationComplete.complete(),
    );
    return animationComplete.future;
  }

  void _showMiddleRewardDialog(BuildContext context, int amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B3E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.gold, width: 2.5),
        ),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFFFEA00),
                    Color(0xFFFF8F00),
                    Color(0xFFB76E00)
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: Color(0xFFFF8F00), blurRadius: 12),
                ],
              ),
              child: const Icon(
                Icons.monetization_on_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'REWARD EARNED!',
              style: GoogleFonts.cinzel(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.gold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '🎉 You earned +$amount Gold Coins!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '500 Gold Coins have been added to your wallet balance!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side:
                        const BorderSide(color: Color(0xFFB8FF65), width: 1.5),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'AWESOME!',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlagWidget(String flag, {double size = 22}) {
    if (flag == '🌐' ||
        flag == 'assets/images/world.png' ||
        flag.contains('world')) {
      return Image.asset(
        'assets/images/world.png',
        width: size * 1.2,
        height: size * 1.0,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Text('🌐', style: TextStyle(fontSize: size)),
      );
    }
    return Text(flag, style: TextStyle(fontSize: size));
  }

  void _showProfileInfoDialog(BuildContext context) {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    final displayCountry =
        (user.country.contains('assets/images') || user.country.isEmpty)
            ? 'World'
            : user.country;

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
                _buildFlagWidget(user.countryFlag, size: 22),
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
              'Country: $displayCountry',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 2),
            Text(
              'Preferred Mode: ${user.preferredGameType.displayName}',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 2),
            Text(
              'Most Played Mode: ${user.mostPlayedGameType.displayName}',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.gold,
                  fontWeight: FontWeight.bold),
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
    final adsConsent = ref.read(adMobConsentServiceProvider);
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
            FutureBuilder<bool>(
              future: adsConsent.isPrivacyOptionsRequired(),
              builder: (context, snapshot) {
                if (snapshot.data != true) return const SizedBox.shrink();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined,
                      color: AppColors.gold),
                  title: Text(
                    'Privacy choices',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  onTap: adsConsent.showPrivacyOptionsForm,
                );
              },
            ),
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
  void dispose() {
    _dailyBonusStartupTimer?.cancel();
    _dailyBonusStartupPoll?.cancel();
    _authSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;
    final playerName = user?.name ?? 'Guest Player';
    final avatarUrl = user?.avatarUrl;
    final countryFlag = user?.countryFlag ?? '🌐';
    final diamonds = user?.diamonds ?? 100;
    final coins = user?.coins ?? 2000;

    final mediaQuery = MediaQuery.sizeOf(context);
    final isTablet = mediaQuery.width >= 650;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ExitGameDialog.show(
          context,
          onYes: () {
            SystemNavigator.pop();
          },
          onNo: () {},
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07122E),
        body: Column(
          children: [
            LobbyHeaderBar(
              playerName: playerName,
              avatarUrl: avatarUrl,
              countryFlag: countryFlag,
              diamonds: diamonds,
              coins: coins,
              coinWalletKey: _walletKey,
              level: 3,
              onProfilePressed: () => _showProfileInfoDialog(context),
              onSettingsPressed: () => _showSettingsDialog(context),
              onInboxPressed: () => _showComingSoonSnackBar('Mailbox Inbox'),
              onShopPressed: () =>
                  _showComingSoonSnackBar('Coin & Diamond Store'),
            ),
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
                        const LobbyCenterGraphic(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: LobbyGameCard(
                                title: 'ONLINE',
                                playerCount: '218,675',
                                cardType: LobbyCardType.online,
                                onTap: () {
                                  OnlineMatchmakingDialog.show(
                                    context,
                                    onMatchFound: (players) {
                                      ref
                                          .read(gameControllerProvider.notifier)
                                          .startNewGame(players: players);
                                      context.push('/game');
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: LobbyGameCard(
                                title: 'TEAM UP',
                                playerCount: '4,144',
                                cardType: LobbyCardType.teamUp,
                                onTap: () =>
                                    _showComingSoonSnackBar('Team Up 2v2'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: LobbyGameCard(
                                title: 'FRIENDS',
                                playerCount: '16,393',
                                cardType: LobbyCardType.friends,
                                onTap: () => _showComingSoonSnackBar(
                                    'Play with Friends'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
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
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => _watchAdAndEarnGold(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFFEA00),
                                  Color(0xFFFF8F00),
                                  Color(0xFFB76E00)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0xFFFF8F00),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Colors.black38,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.ondemand_video_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'WATCH AD & EARN GOLD',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black87,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      Text(
                                        'Watch a short video to claim free gold!',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: AppColors.gold, width: 1.2),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.monetization_on_rounded,
                                          color: AppColors.coinGold, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        '+${AdConfig.adRewardGoldAmount}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.gold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            LobbyBottomNav(
              selectedIndex: _currentNavIndex,
              onTap: (index) {
                setState(() => _currentNavIndex = index);
                if (index != 0) {
                  _showComingSoonSnackBar(
                      index == 1 ? 'Live Voice Chat' : 'Social Hub');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
