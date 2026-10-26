import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/app_constants.dart';

/// Ensures Google Mobile Ads is initialized once before any ad request.
class MobileAdsBootstrap {
  MobileAdsBootstrap._();

  static Future<void>? _initFuture;
  static bool _ready = false;

  /// Google's sample publisher — always shows "Test Ad".
  static const String googleSamplePublisher = 'ca-app-pub-3940256099942544';

  static bool isGoogleSampleUnit(String unitId) =>
      unitId.contains(googleSamplePublisher);

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get isReady => _ready;

  /// Call from [main] and await before [runApp], and from ad widgets before load.
  static Future<void> ensureInitialized() {
    if (!isSupported) {
      return Future.value();
    }
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  static Future<void> _initialize() async {
    try {
      final status = await MobileAds.instance.initialize();
      if (kDebugMode) {
        for (final entry in status.adapterStatuses.entries) {
          debugPrint(
            'AdMob adapter ${entry.key}: ${entry.value.state.name}',
          );
        }
        debugPrint(
          'AdMob units → banner=${AppConstants.admobBannerUnitId} '
          'interstitial=${AppConstants.admobInterstitialUnitId} '
          'native=${AppConstants.admobNativeUnitId}',
        );
      }
      _ready = true;
    } catch (e, st) {
      _initFuture = null;
      if (kDebugMode) {
        debugPrint('MobileAds init failed: $e\n$st');
      }
      rethrow;
    }
  }

  /// Network errors (code 2) often clear after a short wait on emulators.
  static Duration retryDelay(int attempt) =>
      Duration(seconds: 2 + attempt * 3);

  static void logLoadError(String placement, LoadAdError error) {
    if (!kDebugMode) return;
    debugPrint(
      'Ad load failed [$placement] code=${error.code} '
      'domain=${error.domain} message=${error.message}',
    );
  }

  static bool shouldRetry(LoadAdError error) =>
      error.code == 0 || error.code == 2 || error.code == 3;

  /// Header/footer banners refresh together after the first minute.
  static const Duration dashboardBannerCycle = Duration(minutes: 1);

  /// Ads tab: wait after an ad ends before loading the next one.
  static const int adsTabCountdownSeconds = 20;
}
