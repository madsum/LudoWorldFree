import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/ad_config.dart';

final interstitialAdServiceProvider = Provider<InterstitialAdService>((ref) {
  return InterstitialAdService();
});

class InterstitialAdService {
  InterstitialAd? _interstitialAd;
  bool _isAdLoading = false;

  bool get isAdReady => _interstitialAd != null;

  /// Preloads a Fullscreen Interstitial Ad from Google AdMob
  Future<void> preloadAd() async {
    if (_interstitialAd != null || _isAdLoading || kIsWeb) return;

    _isAdLoading = true;

    await InterstitialAd.load(
      adUnitId: AdConfig.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isAdLoading = false;
          debugPrint('🎬 [AdMob] Interstitial Fullscreen Ad loaded successfully.');
        },
        onAdFailedToLoad: (LoadAdError error) {
          _interstitialAd = null;
          _isAdLoading = false;
          debugPrint('❌ [AdMob] Interstitial Ad failed to load: ${error.message}');
        },
      ),
    );
  }

  /// Displays the Fullscreen Interstitial Ad and calls [onAdClosed] when closed or failed
  Future<void> showInterstitialAd({required VoidCallback onAdClosed}) async {
    if (kIsWeb) {
      onAdClosed();
      return;
    }

    if (_interstitialAd == null) {
      await preloadAd();
    }

    if (_interstitialAd == null) {
      debugPrint('ℹ️ [AdMob] Interstitial Ad not available, proceeding to game over screen.');
      onAdClosed();
      return;
    }

    final ad = _interstitialAd!;
    bool callbackFired = false;

    void triggerAdClosed() {
      if (!callbackFired) {
        callbackFired = true;
        onAdClosed();
      }
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        ad.dispose();
        if (identical(_interstitialAd, ad)) _interstitialAd = null;
        preloadAd(); // Preload for next match
        triggerAdClosed();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        ad.dispose();
        if (identical(_interstitialAd, ad)) _interstitialAd = null;
        preloadAd();
        debugPrint('❌ [AdMob] Interstitial Ad failed to show: ${error.message}');
        triggerAdClosed();
      },
    );

    try {
      await ad.show();
    } catch (error) {
      debugPrint('❌ [AdMob] Error showing Interstitial Ad: $error');
      triggerAdClosed();
    }
  }
}
