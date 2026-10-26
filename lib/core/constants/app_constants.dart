import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// App-wide constants for PasswordSaver.
class AppConstants {
  AppConstants._();

  static const String appName = 'PasswordSaver';
  static const String appTagline = 'Your vault. End-to-end encrypted.';

  /// Free trial length in days (requirement 14).
  static const int freeTrialDays = 15;

  /// End of the complimentary trial from [start].
  static DateTime trialEndsAt(DateTime start) =>
      start.add(const Duration(days: freeTrialDays));

  /// Sole admin account (email/password). Skips vault PIN → Admin console.
  static const String adminEmail = 'passwordsaver@gryzion.com';

  /// Accepted admin login IDs on the login screen (map to [adminEmail]).
  static const List<String> adminLoginIds = [
    'admin',
    'passwordsaver',
    'passwordsaver@gryzion.com',
  ];

  static bool isAdminEmail(String? email) =>
      (email ?? '').trim().toLowerCase() == adminEmail.toLowerCase();

  /// Resolves admin login ID / email to Firebase auth email, or null if invalid.
  static String? resolveAdminLoginId(String raw) {
    final id = raw.trim().toLowerCase();
    if (id.isEmpty) return null;
    if (id == adminEmail.toLowerCase()) return adminEmail;
    if (adminLoginIds.any((e) => e.toLowerCase() == id)) return adminEmail;
    return null;
  }

  /// Public privacy policy URL (Google Play Store & website).
  static const String privacyPolicyUrl =
      'https://password-saver-b7f21.web.app/privacy';

  /// Razorpay checkout logo (HTTPS). Set merchant logo in Razorpay Dashboard too.
  static const String razorpayCheckoutLogoUrl =
      'https://password-saver-b7f21.web.app/logo.png';

  /// Label shown on Razorpay checkout (e.g. "PasswordSaver upgrade to 6 month plan").
  static String razorpayCheckoutDescription({
    required int months,
    bool isUpgrade = false,
    bool isRenew = false,
    bool isFilePlan = false,
    bool includeFilePlan = false,
  }) {
    if (isFilePlan) {
      return '$appName $months month file add-on';
    }
    final planPart = (isUpgrade || isRenew)
        ? 'upgrade to $months month plan'
        : '$months month plan';
    var label = '$appName $planPart';
    if (includeFilePlan) label += ' + file plan';
    return label;
  }

  /// Extra free months from invite rewards (points redeem / friend install).
  static const int inviteBonusMonths = 1;

  /// When false, invite-friends UI and point rewards are hidden / no-ops.
  static const bool inviteFriendsEnabled = false;

  /// Points earned each time the user shares the invite.
  static const int inviteSharePoints = 50;

  /// Points required to redeem 1 free month.
  static const int invitePointsPerMonth = 200;

  /// Play Store listing used in invite share links.
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.gryzion.passwordsaver&hl=en_IN';

  /// Subscription plans: months -> price INR (fallback if Firebase config missing).
  static const Map<int, int> subscriptionPlans = {
    3: 100,
    6: 180,
    12: 350,
    24: 650,
  };

  /// Default max attachment files included with each base subscription plan.
  static const Map<int, int> defaultPlanFileLimits = {
    3: 12,
    6: 15,
    12: 20,
    24: 25,
  };

  /// Free-trial attachment file limit.
  static const int defaultTrialFileLimit = 8;

  /// Free file slots for admin-granted lifetime free accounts.
  static const int defaultLifetimeFreeFileLimit = 25;

  /// Soft cap on files attached to a single credential (plan quota still applies).
  static const int maxAttachmentsPerCredential = 20;

  /// Separate file-upgrade plans: months → max files (admin can override).
  static const Map<int, int> defaultFileUpgradeFileCounts = {
    3: 30,
    6: 50,
    12: 100,
    24: 200,
  };

  /// Separate file-upgrade plans: months → price INR.
  static const Map<int, int> defaultFileUpgradePrices = {
    3: 70,
    6: 120,
    12: 200,
    24: 350,
  };

  /// Firestore config doc for plan pricing + file limits.
  static const String colAppConfig = 'appConfig';
  static const String docSubscriptionConfig = 'subscription';

  /// App unlock PIN length (exactly 4 digits).
  static const int appPinLength = 4;

  /// Secure storage keys.
  static const String keyAppPinHash = 'app_pin_hash';
  /// Dedicated PIN salt (do not share with other crypto salts).
  static const String keyAppPinSalt = 'app_pin_salt';
  static const String keyEncryptionSalt = 'encryption_salt';

  /// Firestore fields on `users/{uid}` for PIN (hash only — never plaintext).
  static const String fieldAppPinHash = 'appPinHash';
  static const String fieldAppPinSalt = 'appPinSalt';
  static const String fieldAppPinUpdatedAt = 'appPinUpdatedAt';
  static const String keyMasterKey = 'master_key';

  /// Legacy plaintext field — deleted on login; never write this again.
  static const String fieldMasterKeyBase64 = 'masterKeyBase64';

  /// AES master key encrypted with a key derived from the account secret
  /// (email password, or stable Google account id). Enables cross-device unlock.
  static const String fieldWrappedMasterKey = 'wrappedMasterKey';
  static const String fieldMasterKeyWrapSalt = 'masterKeyWrapSalt';

  /// Secondary wrap with app PIN — recovers vault after Firebase password reset.
  static const String fieldWrappedMasterKeyByPin = 'wrappedMasterKeyByPin';
  static const String fieldMasterKeyPinWrapSalt = 'masterKeyPinWrapSalt';

  /// Last account that owned the on-device master key (avoid wiping on same-user re-login).
  static const String keyLastVaultUid = 'last_vault_uid';
  static const String keyReverifyOnView = 'reverify_on_view';
  static const String keyDeviceLockOnOpen = 'device_lock_on_open';
  static const String keyOnboardingDone = 'onboarding_done';
  static const String keyTermsAccepted = 'terms_accepted';
  static const String keyCustomServices = 'custom_services_json';
  static const String keyServiceChipPriority = 'service_chip_priority_json';
  static const String keyAppThemeId = 'app_theme_id';
  static const String keyInviteShareRewarded = 'invite_share_rewarded';
  static const String keyInviteCodeClaimed = 'invite_code_claimed';
  static const String keyInviteSentCount = 'invite_sent_count';
  static const String keyInvitePoints = 'invite_points';
  static const String keyInviteInstallRewardsClaimed =
      'invite_install_rewards_claimed';

  /// AdMob — Android production app ID, banner, interstitial; native still test until configured.
  static const String admobAppIdAndroid =
      'ca-app-pub-6413436433648714~8349290503';
  static const String admobAppIdIos =
      'ca-app-pub-3940256099942544~1458002511';

  static const String admobBannerAndroid =
      'ca-app-pub-6413436433648714/6781163162';
  static const String admobBannerIos =
      'ca-app-pub-3940256099942544/2934735716';

  static const String admobInterstitialAndroid =
      'ca-app-pub-6413436433648714/3428241514';
  static const String admobInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  static const String admobNativeAndroid =
      'ca-app-pub-3940256099942544/2247696110';
  static const String admobNativeIos =
      'ca-app-pub-3940256099942544/3986624511';

  /// Legacy alias — use [admobBannerUnitId] for platform-specific banner.
  static const String admobBannerUnitIdLegacy = admobBannerAndroid;

  static String get admobAppId => _adUnit(admobAppIdAndroid, admobAppIdIos);

  static String get admobBannerUnitId =>
      _adUnit(admobBannerAndroid, admobBannerIos);

  static String get admobInterstitialUnitId =>
      _adUnit(admobInterstitialAndroid, admobInterstitialIos);

  static String get admobNativeUnitId =>
      _adUnit(admobNativeAndroid, admobNativeIos);

  static String _adUnit(String android, String ios) {
    if (kIsWeb) return android;
    return Platform.isIOS ? ios : android;
  }

  /// Max attachment size before / after compression (1 MB).
  static const int maxAttachmentBytes = 1024 * 1024;

  /// Firestore collections.
  static const String colUsers = 'users';
  static const String colCredentials = 'credentials';
  static const String colGroups = 'groups';
  static const String colSubscriptions = 'subscriptions';
}
