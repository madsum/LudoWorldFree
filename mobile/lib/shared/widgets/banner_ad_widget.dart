import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/ad_config.dart';
import '../../core/ads/ad_mob_consent_service.dart';

/// A top-of-content anchored adaptive banner that never overlays game UI.
class BannerAdWidget extends StatelessWidget {
  const BannerAdWidget({required this.consentService, super.key});

  final AdMobConsentService consentService;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final adUnitId = AdConfig.bannerAdUnitId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final availableWidth = constraints.hasBoundedWidth
            ? math.min(screenWidth, constraints.maxWidth).toDouble()
            : screenWidth;
        return _AdaptiveBanner(
          width: availableWidth,
          orientation: MediaQuery.orientationOf(context),
          adUnitId: adUnitId,
          consentService: consentService,
        );
      },
    );
  }
}

class _AdaptiveBanner extends StatefulWidget {
  const _AdaptiveBanner({
    required this.width,
    required this.orientation,
    required this.adUnitId,
    required this.consentService,
  });

  final double width;
  final Orientation orientation;
  final String adUnitId;
  final AdMobConsentService consentService;

  @override
  State<_AdaptiveBanner> createState() => _AdaptiveBannerState();
}

class _AdaptiveBannerState extends State<_AdaptiveBanner> {
  BannerAd? _bannerAd;
  BannerAd? _pendingAd;
  Timer? _retryTimer;
  int _loadGeneration = 0;
  int _retryCount = 0;
  int? _loadedWidth;

  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  @override
  void didUpdateWidget(covariant _AdaptiveBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width.round() != widget.width.round() ||
        oldWidget.orientation != widget.orientation ||
        oldWidget.adUnitId != widget.adUnitId) {
      _disposeCurrentAds();
      _retryCount = 0;
      _loadBanner();
    }
  }

  Future<void> _loadBanner() async {
    final generation = ++_loadGeneration;
    final width = widget.width.floor();
    final orientation = widget.orientation;
    if (width <= 0) return;

    try {
      if (!await widget.consentService.canRequestAds()) {
        _scheduleRetry(generation);
        return;
      }

      if (!mounted || generation != _loadGeneration) return;

      final size =
          await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
        orientation,
        width,
      );
      if (!mounted || generation != _loadGeneration) return;
      if (size == null) {
        _scheduleRetry(generation);
        return;
      }

      final ad = BannerAd(
        adUnitId: widget.adUnitId,
        request: const AdRequest(),
        size: size,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted || generation != _loadGeneration) {
              ad.dispose();
              return;
            }
            _retryTimer?.cancel();
            _retryTimer = null;
            _retryCount = 0;
            setState(() {
              _pendingAd = null;
              _bannerAd = ad as BannerAd;
              _loadedWidth = width;
            });
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('AdMob banner failed to load: $error');
            ad.dispose();
            if (identical(_pendingAd, ad)) _pendingAd = null;
            _scheduleRetry(generation);
          },
        ),
      );
      _pendingAd = ad;
      await ad.load();
    } catch (error) {
      debugPrint('AdMob banner request failed: $error');
      if (generation == _loadGeneration) {
        _pendingAd?.dispose();
        _pendingAd = null;
        _scheduleRetry(generation);
      }
    }
  }

  void _scheduleRetry(int generation) {
    if (!mounted ||
        generation != _loadGeneration ||
        _retryCount >= _maxRetries) {
      return;
    }
    _retryTimer?.cancel();
    _retryCount++;
    _retryTimer = Timer(Duration(seconds: 2 * _retryCount), () {
      if (!mounted || generation != _loadGeneration) return;
      _retryTimer = null;
      _loadBanner();
    });
  }

  void _disposeCurrentAds() {
    ++_loadGeneration;
    _retryTimer?.cancel();
    _retryTimer = null;
    _bannerAd?.dispose();
    _pendingAd?.dispose();
    _bannerAd = null;
    _pendingAd = null;
    _loadedWidth = null;
  }

  @override
  void dispose() {
    _disposeCurrentAds();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (ad == null || _loadedWidth != widget.width.floor()) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
