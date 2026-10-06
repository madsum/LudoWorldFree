import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Initializes Google Mobile Ads once and gates requests through UMP consent.
class AdMobConsentService {
  Future<void>? _initialization;
  bool _privacyOptionsRequired = false;

  void initialize() {
    _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await MobileAds.instance.initialize();
    await _updateConsent();
  }

  Future<void> _updateConsent() async {
    final completion = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((error) {
            if (error != null) {
              debugPrint(
                'AdMob consent form error ${error.errorCode}: ${error.message}',
              );
            }
          });
          await _refreshPrivacyOptionsRequirement();
        } catch (error) {
          debugPrint('AdMob consent form could not be shown: $error');
        } finally {
          if (!completion.isCompleted) completion.complete();
        }
      },
      (error) async {
        debugPrint(
          'AdMob consent information update failed '
          '${error.errorCode}: ${error.message}',
        );
        // UMP may still allow requests based on its previously stored status.
        await _refreshPrivacyOptionsRequirement();
        if (!completion.isCompleted) completion.complete();
      },
    );
    await completion.future;
  }

  Future<void> _refreshPrivacyOptionsRequirement() async {
    try {
      _privacyOptionsRequired = await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (error) {
      debugPrint('Could not read AdMob privacy options requirement: $error');
    }
  }

  Future<bool> canRequestAds() async {
    initialize();
    try {
      await _initialization;
      return await ConsentInformation.instance.canRequestAds();
    } catch (error) {
      debugPrint('AdMob is unavailable until consent is confirmed: $error');
      return false;
    }
  }

  Future<bool> isPrivacyOptionsRequired() async {
    initialize();
    await _initialization;
    return _privacyOptionsRequired;
  }

  Future<void> showPrivacyOptionsForm() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((error) {
        if (error != null) {
          debugPrint(
            'AdMob privacy options form error '
            '${error.errorCode}: ${error.message}',
          );
        }
      });
    } catch (error) {
      debugPrint('AdMob privacy options form could not be shown: $error');
    }
  }
}

final adMobConsentServiceProvider = Provider<AdMobConsentService>((ref) {
  final service = AdMobConsentService()..initialize();
  return service;
});
