import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/ads/interstitial_ad_service.dart';
import '../../../../core/ads/rewarded_ad_service.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/flying_coin_overlay.dart';
import '../../domain/models/daily_reward_models.dart';
import '../controllers/daily_reward_controller.dart';

class DailyBonusDialog extends ConsumerStatefulWidget {
  const DailyBonusDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x99000000),
      builder: (context) => const DailyBonusDialog(),
    );
  }

  @override
  ConsumerState<DailyBonusDialog> createState() => _DailyBonusDialogState();
}

class _DailyBonusDialogState extends ConsumerState<DailyBonusDialog> {
  Timer? _countdownTimer;
  int _secondsRemaining = 0;
  final GlobalKey _dialogKey = GlobalKey();
  final Map<int, GlobalKey> _cardKeys = {};

  @override
  void initState() {
    super.initState();
    // Preload Interstitial Ad for post-claim playback
    Future.microtask(() {
      ref.read(dailyRewardControllerProvider.notifier).fetchStatus();
      ref.read(interstitialAdServiceProvider).preloadAd();
    });
  }

  GlobalKey _getCardKey(int day) {
    return _cardKeys.putIfAbsent(day, () => GlobalKey());
  }

  void _startCountdownTimer(int totalSeconds) {
    _countdownTimer?.cancel();
    setState(() => _secondsRemaining = totalSeconds);

    if (totalSeconds <= 0) return;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        ref.read(dailyRewardControllerProvider.notifier).fetchStatus();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatCountdown(int seconds) {
    if (seconds <= 0) return '00h:00m:00s';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '${hours}h:${minutes}m:${secs}s';
  }

  void _claimReward(DailyRewardItemModel reward) async {
    final status = ref.read(dailyRewardControllerProvider).status;

    // Allow claim if status is claimable OR if user can claim today and this is active day
    final isEligible = reward.status == RewardItemStatus.claimable ||
        (status.canClaimToday && reward.day == status.activeDay);

    if (!isEligible) return;

    final cardKey = _cardKeys[reward.day];
    final screenSize = MediaQuery.sizeOf(context);
    Offset startOffset = Offset(screenSize.width / 2, screenSize.height / 2);

    if (cardKey?.currentContext != null) {
      final box = cardKey!.currentContext!.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        startOffset = box.localToGlobal(box.size.center(Offset.zero));
      }
    }
    final endOffset = Offset(screenSize.width - 60, 32);

    final controller = ref.read(dailyRewardControllerProvider.notifier);
    final result = await controller.claimDailyReward();

    if (result != null && result.success && mounted) {
      // 1. Trigger Flying Gold Coins Animation Overlay to wallet
      FlyingCoinOverlay.show(
        context,
        startOffset: startOffset,
        endOffset: endOffset,
        onComplete: () async {
          if (!mounted) return;

          // 2. Immediately after flying coin animation completes, show Interstitial Ad!
          final interstitialAdService = ref.read(interstitialAdServiceProvider);
          await interstitialAdService.showInterstitialAd(
            onAdClosed: () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF0D1B3E),
                    content: Text(
                      '🎉 Day ${result.claimedDay} Bonus Claimed! +${result.amount} ${result.rewardType}!',
                      style: GoogleFonts.poppins(
                        color: AppColors.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          );
        },
      );
    }
  }

  void _watchAdForExtraRewards() async {
    final rewardedAdService = ref.read(rewardedAdServiceProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0D1B3E),
        content: Text(
          'Loading Video Ad...',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    await rewardedAdService.showRewardedAd(
      onRewardEarned: (amount, providerRewardId) async {
        final controller = ref.read(dailyRewardControllerProvider.notifier);
        final result = await controller.claimBonusAdReward(providerRewardId);

        if (result != null && result.success && mounted) {
          final screenSize = MediaQuery.sizeOf(context);
          FlyingCoinOverlay.show(
            context,
            startOffset: Offset(screenSize.width / 2, screenSize.height * 0.75),
            endOffset: Offset(screenSize.width - 60, 32),
            onComplete: () {},
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0D1B3E),
              content: Text(
                '🎉 Extra +300 Gold Coins Claimed!',
                style: GoogleFonts.poppins(color: AppColors.gold, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
      },
      onAdClosed: () {},
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0D1B3E),
              content: Text(error, style: GoogleFonts.poppins(color: AppColors.gold)),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rewardState = ref.watch(dailyRewardControllerProvider);
    final status = rewardState.status;

    if (_secondsRemaining == 0 && status.secondsUntilNextClaim > 0 && !status.canClaimToday) {
      _startCountdownTimer(status.secondsUntilNextClaim);
    }

    final rewards = status.rewards;
    final row1 = rewards.length >= 3 ? rewards.sublist(0, 3) : rewards;
    final row2 = rewards.length >= 6 ? rewards.sublist(3, 6) : <DailyRewardItemModel>[];
    final day7 = rewards.length >= 7 ? rewards[6] : null;

    return Dialog(
      key: _dialogKey,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Main Container
          Container(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
            padding: const EdgeInsets.fromLTRB(14, 38, 14, 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1457B8), Color(0xFF092653), Color(0xFF05112B)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.gold, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, 8)),
              ],
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 6),

                  // Top Milestone Progress Bar (Chests at Days 7, 14, 21, 28)
                  _buildMilestoneProgressBar(status),

                  const SizedBox(height: 14),

                  // 7-Day Reward Grid
                  if (rewardState.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(color: AppColors.gold),
                    )
                  else ...[
                    // Row 1 (Days 1, 2, 3)
                    Row(
                      children: row1
                          .map((r) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3.0),
                                  child: _buildRewardCard(r),
                                ),
                              ))
                          .toList(),
                    ),

                    const SizedBox(height: 8),

                    // Row 2 (Days 4, 5, 6)
                    if (row2.isNotEmpty)
                      Row(
                        children: row2
                            .map((r) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 3.0),
                                    child: _buildRewardCard(r),
                                  ),
                                ))
                            .toList(),
                      ),

                    const SizedBox(height: 8),

                    // Row 3 (Day 7 Wide Card)
                    if (day7 != null) _buildDay7WideCard(day7),
                  ],

                  const SizedBox(height: 14),

                  // Footer Section
                  Text(
                    'Come back every day for new reward',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Countdown Label
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Next reward in',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            status.canClaimToday ? 'Available Now!' : _formatCountdown(_secondsRemaining),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: status.canClaimToday ? const Color(0xFF00FF66) : const Color(0xFF00E5FF),
                            ),
                          ),
                        ],
                      ),

                      // Green "Watch Ad for Extra Rewards" Button (+300 Gold)
                      GestureDetector(
                        onTap: status.bonusAdClaimedToday ? null : _watchAdForExtraRewards,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: status.bonusAdClaimedToday
                                ? const LinearGradient(colors: [Colors.grey, Colors.black45])
                                : const LinearGradient(
                                    colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: status.bonusAdClaimedToday
                                ? null
                                : const [
                                    BoxShadow(color: Color(0xFF00E676), blurRadius: 8, offset: Offset(0, 2)),
                                  ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black26,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.ondemand_video_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.monetization_on_rounded,
                                color: AppColors.coinGold,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                status.bonusAdClaimedToday ? 'CLAIMED' : '300',
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
          ),

          // Red Ribbon Header Banner
          Positioned(
            top: -16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF1744), Color(0xFFD50000), Color(0xFF880000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: Text(
                'DAILY BONUS',
                style: GoogleFonts.cinzel(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.gold,
                  letterSpacing: 1.5,
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),

          // Circular Red Close Button (X)
          Positioned(
            top: -12,
            right: -6,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFFFF1744), Color(0xFFB71C1C)],
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Weekly Chest Milestone Progress Bar (Days 7, 14, 21, 28)
  Widget _buildMilestoneProgressBar(DailyRewardStatusModel status) {
    final streak = status.currentStreak;
    final progressFraction = (streak / 28.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0x66081430),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF), width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildChestMilestoneIcon(day: 7, chestType: 'BRONZE', currentStreak: streak, color: const Color(0xFF26A69A)),
              _buildChestMilestoneIcon(day: 14, chestType: 'SILVER', currentStreak: streak, color: const Color(0xFF42A5F5)),
              _buildChestMilestoneIcon(day: 21, chestType: 'GOLD', currentStreak: streak, color: const Color(0xFFFFCA28)),
              _buildChestMilestoneIcon(day: 28, chestType: 'ROYAL', currentStreak: streak, color: const Color(0xFFAB47BC)),
            ],
          ),
          const SizedBox(height: 6),
          // Progress Line
          Stack(
            children: [
              Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progressFraction,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00FF66), Color(0xFF00E5FF)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(color: Color(0xFF00FF66), blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChestMilestoneIcon({
    required int day,
    required String chestType,
    required int currentStreak,
    required Color color,
  }) {
    final unlocked = currentStreak >= day;
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: unlocked ? color : Colors.white24,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.inventory_2_rounded,
                color: unlocked ? color : Colors.white38,
                size: 26,
              ),
            ),
            if (unlocked)
              const Positioned(
                top: -2,
                right: -2,
                child: Icon(Icons.check_circle_rounded, color: Color(0xFF00FF66), size: 14),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.gold, width: 1),
          ),
          child: Text(
            '$day',
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.gold,
            ),
          ),
        ),
      ],
    );
  }

  /// Individual Reward Card (Days 1–6)
  Widget _buildRewardCard(DailyRewardItemModel reward) {
    final status = ref.watch(dailyRewardControllerProvider).status;
    final isClaimed = reward.status == RewardItemStatus.claimed;
    final isClaimable = reward.status == RewardItemStatus.claimable ||
        (status.canClaimToday && reward.day == status.activeDay);

    Color headerColor;
    switch (reward.day % 3) {
      case 1:
        headerColor = const Color(0xFFE91E63);
        break;
      case 2:
        headerColor = const Color(0xFFFFB300);
        break;
      default:
        headerColor = const Color(0xFF8E24AA);
    }

    return GestureDetector(
      key: _getCardKey(reward.day),
      onTap: () => _claimReward(reward),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 125,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isClaimable
                ? [const Color(0xFF1E88E5), const Color(0xFF0D47A1)]
                : [const Color(0xFF0D1B3E), const Color(0xFF091228)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isClaimable
                ? const Color(0xFFFFEA00)
                : (isClaimed ? const Color(0xFF00FF66) : AppColors.gold),
            width: isClaimable ? 2.5 : 1.5,
          ),
          boxShadow: isClaimable
              ? [
                  const BoxShadow(color: Color(0xFFFFEA00), blurRadius: 10, offset: Offset(0, 2)),
                ]
              : null,
        ),
        child: Column(
          children: [
            // Day Tag Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Text(
                'Day ${reward.day}',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),

            // Icon Content
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _getRewardIcon(reward.rewardType, size: 36),

                  // Claimed Overlay
                  if (isClaimed)
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF00FF66),
                        size: 34,
                      ),
                    ),

                  // Locked Overlay
                  if (!isClaimed && !isClaimable)
                    const Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(
                        Icons.lock_rounded,
                        color: AppColors.gold,
                        size: 14,
                      ),
                    ),
                ],
              ),
            ),

            // Amount / Claim Label
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: isClaimable ? const Color(0xFF00E676) : Colors.black45,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Text(
                isClaimable ? 'CLAIM' : reward.label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Day 7 Wide Milestone Card
  Widget _buildDay7WideCard(DailyRewardItemModel reward) {
    final status = ref.watch(dailyRewardControllerProvider).status;
    final isClaimed = reward.status == RewardItemStatus.claimed;
    final isClaimable = reward.status == RewardItemStatus.claimable ||
        (status.canClaimToday && reward.day == status.activeDay);

    return GestureDetector(
      key: _getCardKey(reward.day),
      onTap: () => _claimReward(reward),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isClaimable
                ? [const Color(0xFF1565C0), const Color(0xFF0D47A1)]
                : [const Color(0xFF880E4F), const Color(0xFF4A148C)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isClaimable ? const Color(0xFFFFEA00) : AppColors.gold,
            width: isClaimable ? 2.5 : 1.8,
          ),
          boxShadow: isClaimable
              ? [
                  const BoxShadow(color: Color(0xFFFFEA00), blurRadius: 12, offset: Offset(0, 3)),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Row(
              children: [
                // Chest Graphic
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: Color(0xFF26A69A),
                    size: 42,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Day 7 Milestone',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'BRONZE CHEST',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),

                // Claim Button or Status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isClaimable ? const Color(0xFF00E676) : (isClaimed ? Colors.white24 : Colors.black45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: Text(
                    isClaimable ? 'CLAIM!' : (isClaimed ? 'CLAIMED' : 'LOCKED'),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            if (isClaimed)
              const Center(
                child: Icon(Icons.check_circle_rounded, color: Color(0xFF00FF66), size: 44),
              ),
          ],
        ),
      ),
    );
  }

  Widget _getRewardIcon(String rewardType, {double size = 32}) {
    switch (rewardType.toUpperCase()) {
      case 'SPIN_TOKENS':
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Color(0xFF1565C0),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.stars_rounded, color: const Color(0xFFFFD700), size: size),
        );
      case 'DIAMONDS':
        return Icon(Icons.diamond_rounded, color: AppColors.diamondBlue, size: size);
      case 'CHEST':
        return Icon(Icons.inventory_2_rounded, color: const Color(0xFF26A69A), size: size);
      default:
        return Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: size);
    }
  }
}
