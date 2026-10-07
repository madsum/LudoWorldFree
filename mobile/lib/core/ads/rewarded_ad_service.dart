import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/ad_config.dart';

final rewardedAdServiceProvider = Provider<RewardedAdService>((ref) {
  return RewardedAdService();
});

class RewardedAdService {
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;

  bool get isAdReady => _rewardedAd != null;
  bool get isAdLoading => _isAdLoading;

  /// Preloads a Rewarded Ad from Google AdMob
  Future<void> preloadAd() async {
    if (_rewardedAd != null || _isAdLoading) return;

    _isAdLoading = true;

    await RewardedAd.load(
      adUnitId: AdConfig.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _rewardedAd = ad;
          _isAdLoading = false;
          debugPrint('🎬 [AdMob] Rewarded Ad loaded successfully.');
        },
        onAdFailedToLoad: (LoadAdError error) {
          _rewardedAd = null;
          _isAdLoading = false;
          debugPrint('❌ [AdMob] Rewarded Ad failed to load: ${error.message}');
        },
      ),
    );
  }

  /// Displays the preloaded Rewarded Ad and executes reward callback
  Future<bool> showRewardedAd({
    required Function(int amount, String providerRewardId) onRewardEarned,
    required VoidCallback onAdClosed,
    required Function(String error) onError,
  }) async {
    if (_rewardedAd == null) {
      // Attempt quick load
      await preloadAd();
    }

    if (_rewardedAd == null) {
      onError('Rewarded ad is not ready. Please try again in a few seconds.');
      return false;
    }

    bool earnedReward = false;
    final String rewardEventId = 'ad_reward_${DateTime.now().millisecondsSinceEpoch}';

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        ad.dispose();
        _rewardedAd = null;
        preloadAd(); // Preload next ad
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        ad.dispose();
        _rewardedAd = null;
        preloadAd();
        onError('Ad display failed: ${error.message}');
      },
    );

    await _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem rewardItem) {
        earnedReward = true;
        final int amount = rewardItem.amount.toInt() > 0
            ? rewardItem.amount.toInt()
            : AdConfig.adRewardGoldAmount;

        onRewardEarned(amount, rewardEventId);
      },
    );

    return earnedReward;
  }
}
