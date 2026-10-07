import 'package:flutter/foundation.dart';

/// Configuration for Google Mobile Ads / AdMob Banner and Rewarded Ads.
abstract final class AdConfig {
  static const bool useTestAds = true;

  // Banner Ad Units
  static const String testAndroidBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String productionAndroidBannerAdUnitId =
      'ca-app-pub-6834272256608743/4433726063';

  // Rewarded Ad Units (Official Google AdMob Test Rewarded Ad Unit IDs)
  static const String testAndroidRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String testIOSRewardedAdUnitId =
      'ca-app-pub-3940256099942544/1712485313';
  static const String productionAndroidRewardedAdUnitId =
      'ca-app-pub-6834272256608743/5224354917';

  // Reward Configs
  static const int adRewardGoldAmount = 500;

  static String get bannerAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return useTestAds
          ? testAndroidBannerAdUnitId
          : productionAndroidBannerAdUnitId;
    }
    return useTestAds
        ? testAndroidBannerAdUnitId
        : productionAndroidBannerAdUnitId;
  }

  static String get rewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return useTestAds
          ? testAndroidRewardedAdUnitId
          : productionAndroidRewardedAdUnitId;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return useTestAds ? testIOSRewardedAdUnitId : testAndroidRewardedAdUnitId;
    }
    return testAndroidRewardedAdUnitId;
  }
}
