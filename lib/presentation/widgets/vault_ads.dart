import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/ads/mobile_ads_bootstrap.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Keeps dashboard header/footer banners in sync: header first, both after 1 min.
class VaultBannerCoordinator extends ChangeNotifier {
  VaultBannerCoordinator() {
    _timer = Timer.periodic(MobileAdsBootstrap.dashboardBannerCycle, (_) {
      _onCycle();
    });
  }

  Timer? _timer;
  int refreshGeneration = 0;
  bool footerVisible = true;

  void _onCycle() {
    refreshGeneration++;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

enum VaultBannerSlot { header, footer }

/// Small adaptive banner for dashboard header / footer.
class VaultBannerAd extends StatefulWidget {
  const VaultBannerAd({
    super.key,
    this.placement = 'banner',
    this.compact = false,
    this.coordinator,
    this.slot = VaultBannerSlot.header,
  });

  final String placement;

  /// Shorter header-style banner (max 36dp height, full width).
  final bool compact;

  final VaultBannerCoordinator? coordinator;
  final VaultBannerSlot slot;

  @override
  State<VaultBannerAd> createState() => _VaultBannerAdState();
}

class _VaultBannerAdState extends State<VaultBannerAd> {
  static const int _compactMaxHeight = 36;

  BannerAd? _ad;
  bool _ready = false;
  bool _loading = false;
  int _attempt = 0;
  int _lastGeneration = -1;
  Timer? _retryTimer;
  double? _displayHeight;

  bool get _shouldShow {
    if (widget.slot == VaultBannerSlot.footer &&
        widget.coordinator != null &&
        !widget.coordinator!.footerVisible) {
      return false;
    }
    return _ready && _ad != null;
  }

  @override
  void initState() {
    super.initState();
    widget.coordinator?.addListener(_onCoordinatorChanged);
  }

  bool _loadScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadScheduled) return;
    _loadScheduled = true;
    // Let the first frame paint before AdMob work starts.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _maybeLoad();
    });
  }

  void _onCoordinatorChanged() {
    if (widget.slot == VaultBannerSlot.footer &&
        widget.coordinator != null &&
        !widget.coordinator!.footerVisible) {
      _clearAd();
      return;
    }

    final generation = widget.coordinator?.refreshGeneration ?? 0;
    if (generation != _lastGeneration || _ad == null) {
      _reload();
    }
  }

  void _maybeLoad() {
    if (widget.slot == VaultBannerSlot.footer &&
        widget.coordinator != null &&
        !widget.coordinator!.footerVisible) {
      return;
    }
    if (!_loading && _ad == null) {
      _load();
    }
  }

  Future<void> _reload() async {
    _clearAd();
    if (widget.slot == VaultBannerSlot.footer &&
        widget.coordinator != null &&
        !widget.coordinator!.footerVisible) {
      return;
    }
    await _load(force: true);
  }

  void _clearAd() {
    _retryTimer?.cancel();
    _ad?.dispose();
    _ad = null;
    if (!mounted) return;
    setState(() {
      _ready = false;
      _loading = false;
      _displayHeight = null;
    });
  }

  Future<void> _load({bool force = false}) async {
    if (kIsWeb || !MobileAdsBootstrap.isSupported) return;
    if (!force && _loading) return;
    _loading = true;

    try {
      await MobileAdsBootstrap.ensureInitialized();
      if (!mounted) return;

      final width = MediaQuery.sizeOf(context).width.truncate();
      final AdSize size;
      if (widget.compact) {
        size = AdSize.getInlineAdaptiveBannerAdSize(width, _compactMaxHeight);
      } else {
        final adaptive =
            await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
          width,
        );
        size = adaptive ?? AdSize.banner;
      }
      if (!mounted) return;

      if (kDebugMode) {
        debugPrint(
          'AdMob banner [${widget.placement}] → '
          '${AppConstants.admobBannerUnitId}',
        );
      }

      final banner = BannerAd(
        adUnitId: AppConstants.admobBannerUnitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) async {
            final bannerAd = ad as BannerAd;
            var height = bannerAd.size.height.toDouble();
            if (widget.compact) {
              final platformSize = await bannerAd.getPlatformAdSize();
              if (platformSize != null) {
                height = platformSize.height.toDouble();
              }
            }
            if (!mounted) return;
            setState(() {
              _ready = true;
              _displayHeight = height;
              _attempt = 0;
              _lastGeneration = widget.coordinator?.refreshGeneration ?? 0;
            });
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            MobileAdsBootstrap.logLoadError(widget.placement, error);
            if (!mounted) return;
            setState(() {
              _ad = null;
              _ready = false;
              _loading = false;
              _displayHeight = null;
            });
            _scheduleRetry(error);
          },
        ),
      );
      _ad = banner;
      await banner.load();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Ad load failed [${widget.placement}]: $e');
      }
      if (!mounted) return;
      setState(() {
        _ad = null;
        _ready = false;
        _displayHeight = null;
      });
    } finally {
      if (mounted) _loading = false;
    }
  }

  void _scheduleRetry(LoadAdError error) {
    if (!MobileAdsBootstrap.shouldRetry(error) || _attempt >= 3) return;
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(MobileAdsBootstrap.retryDelay(_attempt), () {
      if (mounted && _ad == null) _load();
    });
  }

  @override
  void dispose() {
    widget.coordinator?.removeListener(_onCoordinatorChanged);
    _retryTimer?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) {
      return const SizedBox.shrink();
    }

    final height = _displayHeight ?? _ad!.size.height.toDouble();
    if (height <= 0) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      height: height,
      child: AdWidget(ad: _ad!),
    );
  }
}

/// Full-screen interstitial + large native ad for the Ads tab.
class VaultAdsTabContent extends StatefulWidget {
  const VaultAdsTabContent({super.key, required this.isActive});

  final bool isActive;

  @override
  State<VaultAdsTabContent> createState() => _VaultAdsTabContentState();
}

class _VaultAdsTabContentState extends State<VaultAdsTabContent> {
  InterstitialAd? _interstitial;
  NativeAd? _nativeAd;
  bool _nativeReady = false;
  bool _interstitialShowing = false;
  int _interstitialAttempt = 0;
  int _nativeAttempt = 0;
  Timer? _interstitialRetry;
  Timer? _nativeRetry;
  Timer? _countdownTimer;
  int _countdownSeconds = 0;
  int _countdownTotalSeconds = MobileAdsBootstrap.adsTabCountdownSeconds;
  String? _lastError;
  bool _hasLoadedOnce = false;
  int _nativeAdKey = 0;

  bool get _isCountingDown => _countdownSeconds > 0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _startLoading();
    }
  }

  void _startCountdown(VoidCallback onComplete, {int? seconds}) {
    _countdownTimer?.cancel();
    if (!mounted) return;
    _countdownTotalSeconds =
        seconds ?? MobileAdsBootstrap.adsTabCountdownSeconds;
    setState(() {
      _lastError = null;
      _countdownSeconds = _countdownTotalSeconds;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds <= 1) {
        timer.cancel();
        setState(() => _countdownSeconds = 0);
        onComplete();
        return;
      }
      setState(() => _countdownSeconds--);
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    if (_countdownSeconds > 0 && mounted) {
      setState(() => _countdownSeconds = 0);
    }
  }

  void _scheduleNextAdCycle() {
    _interstitialRetry?.cancel();
    _nativeRetry?.cancel();
    if (!mounted) return;
    _startCountdown(() {
      if (!mounted) return;
      setState(() => _lastError = null);
      _loadInterstitial();
      _loadNativeAd();
    });
  }

  Future<void> _startLoading() async {
    if (kIsWeb || !MobileAdsBootstrap.isSupported) return;
    try {
      await MobileAdsBootstrap.ensureInitialized();
      if (!mounted) return;
      _hasLoadedOnce = true;
      _loadInterstitial();
      _loadNativeAd();
    } catch (e) {
      if (mounted) {
        setState(() => _lastError = 'AdMob not ready. Check internet connection.');
      }
    }
  }

  @override
  void didUpdateWidget(VaultAdsTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      if (!_hasLoadedOnce) {
        _startLoading();
      } else {
        _showInterstitialIfReady();
      }
    }
  }

  void _loadInterstitial() {
    if (kIsWeb || !MobileAdsBootstrap.isSupported) return;

    if (kDebugMode) {
      debugPrint(
        'AdMob interstitial load → ${AppConstants.admobInterstitialUnitId}',
      );
    }

    InterstitialAd.load(
      adUnitId: AppConstants.admobInterstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          _interstitial?.dispose();
          _interstitial = ad;
          _interstitialAttempt = 0;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (_) {
              _interstitialShowing = true;
            },
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitial = null;
              _interstitialShowing = false;
              _scheduleNextAdCycle();
              if (mounted) setState(() {});
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitial = null;
              _interstitialShowing = false;
              if (kDebugMode) {
                debugPrint(
                  'Interstitial show failed: ${error.code} ${error.message}',
                );
              }
              _scheduleNextAdCycle();
              if (mounted) setState(() {});
            },
          );
          if (widget.isActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showInterstitialIfReady();
            });
          }
        },
        onAdFailedToLoad: (error) {
          _interstitial = null;
          MobileAdsBootstrap.logLoadError('interstitial', error);
          if (!mounted) return;
          setState(() {
            _lastError = _humanMessage(error);
          });
          if (MobileAdsBootstrap.shouldRetry(error) &&
              _interstitialAttempt < 2) {
            _scheduleInterstitialRetry(error);
          } else if (mounted) {
            setState(() => _lastError = _humanMessage(error));
          }
        },
      ),
    );
  }

  void _scheduleInterstitialRetry(LoadAdError error) {
    if (!MobileAdsBootstrap.shouldRetry(error) ||
        _interstitialAttempt >= 3) {
      return;
    }
    _interstitialAttempt++;
    _interstitialRetry?.cancel();
    _interstitialRetry = Timer(
      MobileAdsBootstrap.retryDelay(_interstitialAttempt),
      _loadInterstitial,
    );
  }

  void _showInterstitialIfReady() {
    if (_interstitialShowing || _interstitial == null) return;
    _interstitial!.show();
  }

  void _loadNativeAd() {
    if (kIsWeb || !MobileAdsBootstrap.isSupported) return;

    _nativeAd?.dispose();
    _nativeAd = null;
    if (mounted) {
      setState(() => _nativeReady = false);
    } else {
      _nativeReady = false;
    }

    if (kDebugMode) {
      debugPrint('AdMob native load → ${AppConstants.admobNativeUnitId}');
    }

    final ad = NativeAd(
      adUnitId: AppConstants.admobNativeUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _nativeAd = ad as NativeAd;
            _nativeReady = true;
            _nativeAdKey++;
            _nativeAttempt = 0;
            _lastError = null;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          MobileAdsBootstrap.logLoadError('native', error);
          if (!mounted) return;
          setState(() {
            _nativeAd = null;
            _nativeReady = false;
            _lastError = _humanMessage(error);
          });
          _scheduleNativeRetry(error);
          if (_nativeAttempt >= 2 && mounted) {
            setState(() => _lastError = _humanMessage(error));
          }
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: AppColors.foam,
        cornerRadius: 16,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: AppColors.teal,
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.ink,
          style: NativeTemplateFontStyle.bold,
          size: 16,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.slate,
          style: NativeTemplateFontStyle.normal,
          size: 13,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.mist,
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
      ),
    );
    ad.load();
  }

  void _scheduleNativeRetry(LoadAdError error) {
    if (!MobileAdsBootstrap.shouldRetry(error) || _nativeAttempt >= 3) {
      return;
    }
    _nativeAttempt++;
    _nativeRetry?.cancel();
    _nativeRetry = Timer(
      MobileAdsBootstrap.retryDelay(_nativeAttempt),
      _loadNativeAd,
    );
  }

  String _humanMessage(LoadAdError error) {
    switch (error.code) {
      case 2:
        return 'Network error. Use Google Play emulator or check internet, then retry.';
      case 3:
        return 'No ad available right now. Try again in a moment.';
      default:
        return 'Ad could not load (code ${error.code}).';
    }
  }

  @override
  void dispose() {
    _cancelCountdown();
    _interstitialRetry?.cancel();
    _nativeRetry?.cancel();
    _interstitial?.dispose();
    _nativeAd?.dispose();
    super.dispose();
  }

  Widget _buildCountdownPanel({bool compact = false}) {
    if (!_isCountingDown) return const SizedBox.shrink();

    final progress = _countdownTotalSeconds <= 0
        ? 0.0
        : 1 - (_countdownSeconds / _countdownTotalSeconds.toDouble());

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 20,
        vertical: compact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.foam.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: AppColors.mist.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: compact ? 4 : 6,
              backgroundColor: AppColors.mist.withValues(alpha: 0.25),
              color: AppColors.teal,
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            'Next ad loading in ${_countdownSeconds}s',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_interstitialShowing) {
      return const SizedBox.shrink();
    }

    if (_nativeReady && _nativeAd != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Center(
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight.clamp(280, 600),
                  child: AdWidget(
                    key: ValueKey(_nativeAdKey),
                    ad: _nativeAd!,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _buildCountdownPanel(compact: true),
              ),
            ],
          );
        },
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const VaultBannerAd(placement: 'ads_tab'),
            const SizedBox(height: 20),
            Icon(Icons.campaign_outlined, size: 48, color: AppColors.mist),
            const SizedBox(height: 12),
            if (_isCountingDown)
              _buildCountdownPanel()
            else
              Text(
                _lastError ?? 'Loading sponsored content…',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            if (_lastError != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _interstitialAttempt = 0;
                  _nativeAttempt = 0;
                  setState(() => _lastError = null);
                  _loadInterstitial();
                  _loadNativeAd();
                },
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Returns true when Google Mobile Ads can run on this platform.
bool get isMobileAdsSupported => MobileAdsBootstrap.isSupported;
