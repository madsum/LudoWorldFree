import 'package:flutter/foundation.dart';

/// Simple switch between Google test ads and the production banner unit.
abstract final class AdConfig {
  static const bool useTestAds = true;
  static const String testAndroidBannerAdUnitId =
      'ca-app-pub-3940256099942544/9214589741';
  static const String productionAndroidBannerAdUnitId =
      'ca-app-pub-6834272256608743/4433726063';

  static const String androidBannerAdUnitId =
      useTestAds ? testAndroidBannerAdUnitId : productionAndroidBannerAdUnitId;

  static String? get bannerAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return androidBannerAdUnitId;
    }
    return null;
  }
}
