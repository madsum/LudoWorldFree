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

  /// Displays the preloaded Rewarded Ad and executes instant reward callback
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

    final ad = _rewardedAd!;
    final rewardEventId = 'ad_reward_${DateTime.now().microsecondsSinceEpoch}';
    bool earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        ad.dispose();
        if (identical(_rewardedAd, ad)) _rewardedAd = null;
        unawaited(preloadAd()); // Preload next ad
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        ad.dispose();
        if (identical(_rewardedAd, ad)) _rewardedAd = null;
        unawaited(preloadAd());
        onError('Ad display failed: ${error.message}');
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem rewardItem) {
          earned = true;
          // Trigger instant callback with full configured gold reward amount (500 coins)
          onRewardEarned(AdConfig.adRewardGoldAmount, rewardEventId);
        },
      );
    } catch (error) {
      onError('Ad display failed: $error');
    }

    return earned;
  }
}
