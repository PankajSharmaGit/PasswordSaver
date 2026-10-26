import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/payments/razorpay_cloud_functions.dart';
import '../../core/pricing/subscription_catalog_service.dart';
import '../../core/pricing/subscription_pricing.dart';
import '../../core/security/biometric_service.dart';
import '../../core/security/device_info_service.dart';
import '../../core/security/encryption_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/storage/attachment_storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/user/user_cloud_functions.dart';
import '../../core/utils/string_formatters.dart';
import '../../data/local/hive_boxes.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/credential_repository_impl.dart';
import '../../data/repositories/pin_subscription_repository_impl.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/platform_category.dart';
import '../../domain/entities/service_chip_ref.dart';
import '../../domain/repositories/repositories.dart';

/// App-wide session and vault state.
class VaultAppState extends ChangeNotifier {
  VaultAppState({
    required AuthRepository authRepository,
    required CredentialRepository credentialRepository,
    required PinRepository pinRepository,
    required SubscriptionRepository subscriptionRepository,
    required SecureStorageService storage,
    required BiometricService biometricService,
    required DeviceInfoService deviceInfoService,
    AppThemeId initialThemeId = AppThemeId.cobalt,
  })  : _auth = authRepository,
        _credentials = credentialRepository,
        _pin = pinRepository,
        _subscription = subscriptionRepository,
        _storage = storage,
        _biometric = biometricService,
        _deviceInfo = deviceInfoService,
        themeId = initialThemeId;

  final AuthRepository _auth;
  final CredentialRepository _credentials;
  final PinRepository _pin;
  final SubscriptionRepository _subscription;
  final SecureStorageService _storage;
  final BiometricService _biometric;
  final DeviceInfoService _deviceInfo;
  final _enc = EncryptionService.instance;
  final _attachments = AttachmentStorageService();
  final _uuid = const Uuid();
  final _catalogService = SubscriptionCatalogService();
  final _userCloud = UserCloudFunctions();

  AppUser? user;
  bool isLoading = false;
  String? errorMessage;
  /// Set when email login works but vault key still uses the old password.
  VaultKeyUnlockFailure? pendingVaultRecovery;
  bool pinUnlocked = false;
  bool hasPin = false;
  bool reverifyOnView = true;
  bool termsAccepted = false;
  List<CredentialEntry> credentials = [];
  bool firebaseReady = false;

  /// Admin-controlled plan pricing + file limits.
  SubscriptionCatalog subscriptionCatalog = SubscriptionCatalog.defaults();

  /// When true, every app open / resume requires system device lock.
  bool deviceLockOnOpen = false;

  /// Last successful system device-lock verification (avoids double prompt).
  DateTime? deviceLockVerifiedAt;

  /// True if device lock was verified recently (within 90 seconds).
  bool get isDeviceLockFresh {
    if (deviceLockVerifiedAt == null) return false;
    return DateTime.now().difference(deviceLockVerifiedAt!) <
        const Duration(seconds: 90);
  }

  /// Credentials that currently have an attachment file.
  int get attachmentFileCount =>
      credentials.fold<int>(0, (sum, c) => sum + c.attachmentCount);

  /// Max files = base/trial free files + active file-upgrade plan (added).
  int get attachmentFileLimit {
    final u = user;
    if (u == null) return subscriptionCatalog.trialMaxAttachmentFiles;

    final base = u.isLifetimeFree
        ? AppConstants.defaultLifetimeFreeFileLimit
        : ((!u.isTrialActive && u.subscriptionPlanMonths != null)
            ? subscriptionCatalog.fileLimitForMonths(
                u.subscriptionPlanMonths,
                isTrialActive: false,
              )
            : subscriptionCatalog.trialMaxAttachmentFiles);

    final upgrade =
        (u.hasActiveFilePlan && u.filePlanMaxFiles != null) ? u.filePlanMaxFiles! : 0;
    return base + upgrade;
  }

  /// Free files from trial / base subscription only.
  int get baseAttachmentFileLimit {
    final u = user;
    if (u == null) return subscriptionCatalog.trialMaxAttachmentFiles;
    if (u.isLifetimeFree) return AppConstants.defaultLifetimeFreeFileLimit;
    if (!u.isTrialActive && u.subscriptionPlanMonths != null) {
      return subscriptionCatalog.fileLimitForMonths(
        u.subscriptionPlanMonths,
        isTrialActive: false,
      );
    }
    return subscriptionCatalog.trialMaxAttachmentFiles;
  }

  /// Extra files from purchased file-upgrade plan.
  int get upgradeAttachmentFileLimit {
    final u = user;
    if (u == null || !u.hasActiveFilePlan) return 0;
    return u.filePlanMaxFiles ?? 0;
  }

  /// Every attached file, oldest-first — first [baseAttachmentFileLimit] are free slots.
  List<({CredentialEntry entry, CredentialAttachment file})>
      get attachmentFilesOldestFirst {
    final list = <({CredentialEntry entry, CredentialAttachment file})>[];
    for (final c in credentials) {
      for (final f in c.effectiveAttachments) {
        list.add((entry: c, file: f));
      }
    }
    list.sort((a, b) {
      final aAt = a.file.createdAt ??
          a.entry.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.file.createdAt ??
          b.entry.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = aAt.compareTo(bAt);
      if (byDate != 0) return byDate;
      final byEntry = a.entry.id.compareTo(b.entry.id);
      if (byEntry != 0) return byEntry;
      return a.file.id.compareTo(b.file.id);
    });
    return list;
  }

  /// True when this file sits beyond the free base quota (needs file plan).
  bool isUpgradeAttachment(
    CredentialEntry entry, [
    CredentialAttachment? file,
  ]) {
    final target = file ??
        (entry.effectiveAttachments.isNotEmpty
            ? entry.effectiveAttachments.first
            : null);
    if (target == null) return false;
    final ordered = attachmentFilesOldestFirst;
    final index = ordered.indexWhere(
      (e) => e.entry.id == entry.id && e.file.id == target.id,
    );
    if (index < 0) return false;
    return index >= baseAttachmentFileLimit;
  }

  /// Base free files open after base renew; upgrade-slot files need active file plan.
  bool canOpenAttachment(
    CredentialEntry entry, [
    CredentialAttachment? file,
  ]) {
    final target = file ??
        (entry.effectiveAttachments.isNotEmpty
            ? entry.effectiveAttachments.first
            : null);
    if (target == null) return false;
    final u = user;
    if (u == null || !u.hasActiveAccess) return false;
    if (!isUpgradeAttachment(entry, target)) return true;
    return u.hasActiveFilePlan;
  }

  /// True when the user can attach at least [count] new file(s).
  bool canAddAttachments(int count) {
    if (count <= 0) return true;
    return attachmentFileCount + count <= attachmentFileLimit;
  }

  /// True when the user can attach a *new* file.
  bool get canAddAttachment => canAddAttachments(1);

  String get attachmentUsageLabel {
    final upgrade = upgradeAttachmentFileLimit;
    if (upgrade > 0) {
      return '$attachmentFileCount / $attachmentFileLimit files '
          '(${baseAttachmentFileLimit} free + $upgrade upgrade)';
    }
    return '$attachmentFileCount / $attachmentFileLimit files';
  }

  /// User-added manual services (e.g. Sarkari Result, HDFC).
  List<String> customServices = [];

  /// Ordered services for dashboard chips (priority = list index).
  List<ServiceChipRef> chipPriority = ServiceChipRef.defaultPriority();

  /// Offline mutations waiting to push to Firebase.
  int unsyncedCount = 0;

  /// Last successful Hive ↔ cloud sync time.
  DateTime? lastSyncedAt;

  /// True while a sync is running.
  bool isSyncing = false;

  /// Selected vault appearance (persisted).
  AppThemeId themeId;

  /// Invite points (50 per share; 200 = 1 free month).
  int invitePoints = 0;

  /// True after this account used someone else's invite code (install registered).
  bool inviteCodeClaimed = false;

  /// How many times the user shared the invite.
  int inviteSentCount = 0;

  /// How many friend-install free months already granted to this inviter.
  int inviteInstallRewardsClaimed = 0;

  /// True when trial/subscription expired — user must upgrade.
  bool get subscriptionRequired {
    final u = user;
    if (u == null) return false;
    return !u.hasActiveAccess;
  }

  /// Home bottom banner ads — off while a paid plan is active.
  bool get showHomeFooterAds => user?.hasPaidPlan != true;

  AuthRepository get auth => _auth;
  PinRepository get pinRepo => _pin;
  SubscriptionRepository get subscriptionRepo => _subscription;
  BiometricService get biometric => _biometric;
  DeviceInfoService get deviceInfo => _deviceInfo;
  SecureStorageService get storage => _storage;

  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();
    try {
      firebaseReady = FirebaseAvailability.isAvailable;
      if (_auth is AuthRepositoryImpl) {
        await _auth.bootstrap();
      }
      user = _auth.currentUser;
      user = _auth.currentUser;
      if (user != null) {
        if (_pin case final PinRepositoryImpl pinImpl) {
          await pinImpl.syncFromFirebase();
          await pinImpl.pushLocalPinToFirebaseIfNeeded();
        }
      }
      hasPin = await _pin.hasPin();
      reverifyOnView = await _storage.getReverifyOnView();
      deviceLockOnOpen = await _storage.getDeviceLockOnOpen();
      themeId = AppThemeIdX.fromStorage(await _storage.getAppThemeId());
      AppColors.apply(VaultPalette.of(themeId));
      invitePoints = int.tryParse(
            await _storage.read(AppConstants.keyInvitePoints) ?? '0',
          ) ??
          0;
      inviteCodeClaimed =
          (await _storage.read(AppConstants.keyInviteCodeClaimed)) == 'true';
      inviteSentCount = int.tryParse(
            await _storage.read(AppConstants.keyInviteSentCount) ?? '0',
          ) ??
          0;
      inviteInstallRewardsClaimed = int.tryParse(
            await _storage.read(AppConstants.keyInviteInstallRewardsClaimed) ??
                '0',
          ) ??
          0;
      termsAccepted =
          (await _storage.read('terms_accepted')) == 'true';
      await _loadCustomServices();
      await _loadChipPriority();
      if (user != null) {
        credentials = await _credentials.getCredentials(user!.uid);
        refreshSyncStatus(notify: false);
      }
      // Cloud sync, catalog, and demo cleanup must not block the first screen.
      unawaited(_warmAfterLaunch());
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Network work that used to run before splash could leave the screen.
  Future<void> _warmAfterLaunch() async {
    try {
      if (user == null) return;
      if (credentials.any((c) => c.isDemoSample)) {
        await _clearDemoSamples();
        credentials = await _credentials.getCredentials(user!.uid);
      }
      await refreshSubscriptionFromFirebase();
      await refreshSubscriptionCatalog(notify: false);
      refreshSyncStatus(notify: false);
      await autoSyncIfNeeded();
      if (AppConstants.inviteFriendsEnabled) {
        await syncInviteInstallRewards();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, String>> collectDevice() =>
      _deviceInfo.collectDeviceDetails();

  Future<void> _loadCustomServices() async {
    try {
      final raw = await _storage.read(AppConstants.keyCustomServices);
      if (raw == null || raw.isEmpty) {
        customServices = [];
        return;
      }
      final list = jsonDecode(raw) as List<dynamic>;
      customServices = list
          .map((e) => StringFormatters.toTitleCase(e.toString()))
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      customServices = [];
    }
  }

  /// Loads saved chip order; merges any missing builtins / manual services.
  Future<void> _loadChipPriority() async {
    try {
      final raw = await _storage.read(AppConstants.keyServiceChipPriority);
      List<ServiceChipRef> loaded = [];
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          if (item is Map) {
            final ref =
                ServiceChipRef.fromJson(Map<String, dynamic>.from(item));
            if (ref != null) loaded.add(ref);
          }
        }
      }
      chipPriority = _mergeChipPriority(loaded);
      await _persistChipPriority();
    } catch (_) {
      chipPriority = _mergeChipPriority([]);
    }
  }

  /// Ensures every built-in + manual service exists exactly once in order.
  List<ServiceChipRef> _mergeChipPriority(List<ServiceChipRef> loaded) {
    final seen = <String>{};
    final result = <ServiceChipRef>[];

    void add(ServiceChipRef ref) {
      if (seen.add(ref.storageKey)) result.add(ref);
    }

    for (final ref in loaded) {
      if (ref.isCustom) {
        final stillExists = customServices.any(
          (s) => s.toLowerCase() == ref.customName!.toLowerCase(),
        );
        if (stillExists) add(ref);
      } else {
        add(ref);
      }
    }

    // Append any missing defaults / customs at the end
    for (final ref in ServiceChipRef.defaultPriority()) {
      add(ref);
    }
    for (final name in customServices) {
      add(ServiceChipRef.custom(name));
    }
    return result;
  }

  Future<void> _persistChipPriority() async {
    await _storage.write(
      AppConstants.keyServiceChipPriority,
      jsonEncode(chipPriority.map((e) => e.toJson()).toList()),
    );
  }

  /// Drag-reorder chip priority in View more (index 0 = highest priority).
  Future<void> reorderChipPriority(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= chipPriority.length ||
        newIndex < 0 ||
        newIndex > chipPriority.length) {
      return;
    }
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final list = List<ServiceChipRef>.from(chipPriority);
    final item = list.removeAt(oldIndex);
    list.insert(target, item);
    chipPriority = list;
    await _persistChipPriority();
    notifyListeners();
  }

  /// Moves [ref] to the front of the chip bar (priority 1).
  Future<void> pinServiceToTop(ServiceChipRef ref) async {
    final list = List<ServiceChipRef>.from(chipPriority)
      ..removeWhere((e) => e.storageKey == ref.storageKey);
    list.insert(0, ref);
    chipPriority = list;
    await _persistChipPriority();
    notifyListeners();
  }

  /// Adds a manual service name (e.g. Sarkari Result) — Title Case every word.
  Future<bool> addCustomService(String name) async {
    final titled = StringFormatters.toTitleCase(name);
    if (titled.isEmpty) {
      errorMessage = 'Service name is required';
      notifyListeners();
      return false;
    }
    final exists = customServices.any(
      (s) => s.toLowerCase() == titled.toLowerCase(),
    );
    if (exists) {
      errorMessage = 'Service already exists';
      notifyListeners();
      return false;
    }
    // Also skip if it matches a built-in platform label
    final builtin = PlatformInfo.all.any(
      (p) => StringFormatters.toTitleCase(p.label).toLowerCase() ==
          titled.toLowerCase(),
    );
    if (builtin) {
      errorMessage = 'This service already exists in the list';
      notifyListeners();
      return false;
    }

    customServices = [...customServices, titled];
    await _storage.write(
      AppConstants.keyCustomServices,
      jsonEncode(customServices),
    );
    // New manual service gets top chip priority so it appears on the bar
    final ref = ServiceChipRef.custom(titled);
    chipPriority = [
      ref,
      ...chipPriority.where((e) => e.storageKey != ref.storageKey),
    ];
    await _persistChipPriority();
    errorMessage = null;
    notifyListeners();
    return true;
  }

  Future<void> removeCustomService(String name) async {
    customServices = customServices
        .where((s) => s.toLowerCase() != name.toLowerCase())
        .toList();
    await _storage.write(
      AppConstants.keyCustomServices,
      jsonEncode(customServices),
    );
    chipPriority = chipPriority
        .where(
          (e) =>
              !(e.isCustom &&
                  e.customName!.toLowerCase() == name.toLowerCase()),
        )
        .toList();
    await _persistChipPriority();
    notifyListeners();
  }

  /// Pulls trial / paid plan from Firestore (`subscriptions` + `users`).
  Future<void> refreshSubscriptionFromFirebase() async {
    if (user == null) return;
    final repo = _subscription;
    if (repo is! SubscriptionRepositoryImpl) return;
    try {
      final status = await repo.fetchStatus(user!.uid);
      if (status.isLifetimeFree) {
        user = user!.copyWith(
          trialStartedAt: status.trialStartedAt ?? user!.trialStartedAt,
          isTrialActive: false,
          isLifetimeFree: true,
          clearPlanMonths: true,
          clearSubscriptionExpiry: true,
        );
        return;
      }

      // Ensure a trial doc exists for older accounts that only had user fields.
      if (status.expiresAt == null && user!.createdAt != null) {
        final trialEnd = AppConstants.trialEndsAt(user!.createdAt!);
        await repo.saveTrial(
          userId: user!.uid,
          startedAt: user!.createdAt!,
          expiresAt: trialEnd,
        );
        user = user!.copyWith(
          trialStartedAt: user!.createdAt,
          subscriptionExpiresAt: trialEnd,
          lastExpiresAt: trialEnd,
          isTrialActive: true,
          isLifetimeFree: false,
          clearPlanMonths: true,
        );
        return;
      }

      user = user!.copyWith(
        trialStartedAt: status.trialStartedAt ?? user!.trialStartedAt,
        subscriptionExpiresAt: status.expiresAt ?? user!.subscriptionExpiresAt,
        lastExpiresAt: status.lastExpiresAt ??
            status.expiresAt ??
            user!.lastExpiresAt,
        isTrialActive: status.isTrialActive,
        isLifetimeFree: false,
        subscriptionPlanMonths: status.planMonths,
        clearPlanMonths: status.planMonths == null,
      );
    } catch (e) {
      debugPrint('refreshSubscriptionFromFirebase failed: $e');
    }
  }

  Future<bool> signUp({
    required String displayName,
    required String userId,
    required String email,
    required String password,
    required String primaryMobile,
    String? secondaryMobile,
  }) async {
    return _run(() async {
      final device = await collectDevice();
      user = await _auth.signUp(
        displayName: displayName,
        userId: userId,
        email: email,
        password: password,
        primaryMobile: primaryMobile,
        secondaryMobile: secondaryMobile,
        deviceDetails: device,
      );
      credentials = [];
      pinUnlocked = false;
      await _ensureTrialOnFirebase();
    });
  }

  Future<bool> signInEmail(String email, String password) async {
    pendingVaultRecovery = null;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final device = await collectDevice();
      user = await _auth.signInWithEmail(
        email: email,
        password: password,
        deviceDetails: device,
      );
      hasPin = await _pin.hasPin();
      pinUnlocked = false;
      credentials = await _credentials.getCredentials(user!.uid);
      refreshSyncStatus(notify: false);
      if (_pin case final PinRepositoryImpl pinImpl) {
        await pinImpl.syncFromFirebase();
        hasPin = await _pin.hasPin();
      }
      await refreshSubscriptionFromFirebase();
      await autoSyncIfNeeded();
      return true;
    } on VaultKeyUnlockFailure catch (e) {
      pendingVaultRecovery = e;
      errorMessage = e.message;
      return false;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// After password reset: unlock existing vault with app PIN, then continue login.
  Future<bool> recoverVaultWithPin(String pin) async {
    final pending = pendingVaultRecovery;
    if (pending == null) return false;
    final auth = _auth;
    if (auth is! AuthRepositoryImpl) return false;
    return _run(() async {
      await auth.recoverVaultWithPin(
        uid: pending.uid,
        newPassword: pending.newPassword,
        pin: pin,
      );
      await auth.syncPinVaultWrap(pin);
      final device = await collectDevice();
      // Reload session user doc now that vault key is available.
      final fbUser = await auth.reloadCurrentUser();
      if (fbUser == null) {
        throw Exception('Signed in user missing after vault recovery');
      }
      user = fbUser.copyWith(deviceDetails: device);
      hasPin = await _pin.hasPin();
      pinUnlocked = false;
      credentials = await _credentials.getCredentials(user!.uid);
      refreshSyncStatus(notify: false);
      if (_pin case final PinRepositoryImpl pinImpl) {
        await pinImpl.syncFromFirebase();
        hasPin = await _pin.hasPin();
      }
      await refreshSubscriptionFromFirebase();
      pendingVaultRecovery = null;
      await autoSyncIfNeeded();
    });
  }

  /// After password reset with no recoverable key: new empty vault (old passwords lost).
  Future<bool> startFreshVaultAfterPasswordReset({String? pin}) async {
    final pending = pendingVaultRecovery;
    if (pending == null) return false;
    final auth = _auth;
    if (auth is! AuthRepositoryImpl) return false;
    return _run(() async {
      await auth.startFreshVault(
        uid: pending.uid,
        newPassword: pending.newPassword,
        pin: pin,
      );
      final device = await collectDevice();
      final fbUser = await auth.reloadCurrentUser();
      if (fbUser == null) {
        // Ensure user doc exists for navigation even if reload is empty.
        user = AppUser(
          uid: pending.uid,
          email: '',
          displayName: 'User',
          userId: pending.uid,
          deviceDetails: device,
          emailVerified: true,
          createdAt: DateTime.now(),
        );
      } else {
        user = fbUser.copyWith(deviceDetails: device);
      }
      hasPin = await _pin.hasPin();
      pinUnlocked = false;
      credentials = [];
      refreshSyncStatus(notify: false);
      await refreshSubscriptionFromFirebase();
      pendingVaultRecovery = null;
    });
  }

  Future<bool> signInGoogle() async {
    final ok = await _run(() async {
      final device = await collectDevice();
      user = await _auth.signInWithGoogle(deviceDetails: device);
      hasPin = await _pin.hasPin();
      pinUnlocked = false;
      credentials = await _credentials.getCredentials(user!.uid);
      refreshSyncStatus(notify: false);
      if (_pin case final PinRepositoryImpl pinImpl) {
        await pinImpl.syncFromFirebase();
        hasPin = await _pin.hasPin();
      }
      await _ensureTrialOnFirebase();
      await refreshSubscriptionFromFirebase();
    });
    if (ok) await autoSyncIfNeeded();
    return ok;
  }

  /// Creates `subscriptions/{uid}` trial doc when missing (new Google / email).
  Future<void> _ensureTrialOnFirebase() async {
    if (user == null) return;
    final repo = _subscription;
    if (repo is! SubscriptionRepositoryImpl) return;
    final existing = await repo.fetchStatus(user!.uid);
    if (existing.expiresAt != null) return;

    final started = user!.createdAt ?? DateTime.now();
    final expires =
        user!.subscriptionExpiresAt ?? AppConstants.trialEndsAt(started);
    await repo.saveTrial(
      userId: user!.uid,
      startedAt: started,
      expiresAt: expires,
    );
    user = user!.copyWith(
      trialStartedAt: started,
      subscriptionExpiresAt: expires,
      lastExpiresAt: expires,
      isTrialActive: true,
      clearPlanMonths: true,
    );
  }

  Future<bool> resetPassword(String email) async {
    return _run(() async {
      await _auth.sendPasswordResetEmail(email);
    });
  }

  Future<void> signOut() async {
    await _auth.signOut();
    user = null;
    credentials = [];
    pinUnlocked = false;
    unsyncedCount = 0;
    lastSyncedAt = null;
    isSyncing = false;
    notifyListeners();
  }

  /// Removes all demo/sample credentials (legacy guest preview data).
  Future<void> _clearDemoSamples() async {
    if (user == null) return;
    final demos = credentials.where((c) => c.isDemoSample).toList();
    if (demos.isEmpty) return;

    for (final demo in demos) {
      await _credentials.deleteCredential(user!.uid, demo.id);
    }
    credentials = credentials.where((c) => !c.isDemoSample).toList();
    await _storage.write('demo_samples_cleared', 'true');
  }

  Future<bool> createAppPin(String pin) async {
    return _run(() async {
      await _pin.createPin(pin);
      hasPin = true;
      pinUnlocked = true;
      if (_auth case final AuthRepositoryImpl auth) {
        await auth.syncPinVaultWrap(pin);
      }
    });
  }

  Future<bool> unlockWithPin(String pin) async {
    final ok = await _pin.verifyPin(pin);
    if (ok) {
      pinUnlocked = true;
      errorMessage = null;
      return true;
    }
    errorMessage = 'Incorrect app PIN';
    notifyListeners();
    return false;
  }

  Future<bool> unlockWithBiometric() async {
    final ok = await _biometric.authenticate(
      reason: 'Unlock PasswordSaver vault',
    );
    if (ok) {
      pinUnlocked = true;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> updateAppPin(String oldPin, String newPin) async {
    return _run(() async {
      final ok = await _pin.updatePin(oldPin: oldPin, newPin: newPin);
      if (!ok) throw Exception('Old PIN is incorrect');
      if (_auth case final AuthRepositoryImpl auth) {
        await auth.syncPinVaultWrap(newPin);
      }
    });
  }

  Future<bool> recoverAndResetPin({
    String? email,
    String? primaryMobile,
    String? secondaryMobile,
    String? rememberedPin,
    required String newPin,
  }) async {
    return _run(() async {
      final verified = await _auth.verifyRecovery(
        email: email,
        primaryMobile: primaryMobile,
        secondaryMobile: secondaryMobile,
        appPin: rememberedPin,
      );
      if (!verified) {
        throw Exception(
          'Need at least two matching factors (email, mobile, or PIN)',
        );
      }
      await _pin.resetPin(newPin);
      hasPin = true;
      pinUnlocked = true;
      if (_auth case final AuthRepositoryImpl auth) {
        await auth.syncPinVaultWrap(newPin);
      }
    });
  }

  /// Toggles PIN-on-view. Changing the switch always requires current app PIN.
  Future<bool> setReverifyOnView(bool enabled, {required String pin}) async {
    hasPin = await _pin.hasPin();
    if (!hasPin) {
      errorMessage = 'Create an app PIN first';
      notifyListeners();
      return false;
    }
    final ok = await _pin.verifyPin(pin);
    if (!ok) {
      errorMessage = 'Incorrect app PIN';
      notifyListeners();
      return false;
    }
    reverifyOnView = enabled;
    await _storage.setReverifyOnView(enabled);
    errorMessage = null;
    notifyListeners();
    return true;
  }

  /// Switches vault appearance and persists the choice.
  Future<void> setThemeId(AppThemeId id) async {
    themeId = id;
    AppColors.apply(VaultPalette.of(id));
    await _storage.setAppThemeId(id.name);
    notifyListeners();
  }

  /// Enables system device lock gate. Verifies device auth once before saving.
  Future<bool> setDeviceLockOnOpen(bool enabled) async {
    if (enabled) {
      final can = await _biometric.canAuthenticate();
      if (!can) {
        errorMessage =
            'No device lock found. Set PIN, pattern, or fingerprint in phone Settings first.';
        notifyListeners();
        return false;
      }
      final ok = await verifyDeviceLock(
        reason: 'Verify device lock to enable app protection',
      );
      if (!ok) {
        errorMessage = 'Device verification failed. Setting not enabled.';
        notifyListeners();
        return false;
      }
    } else {
      deviceLockVerifiedAt = null;
    }
    deviceLockOnOpen = enabled;
    await _storage.setDeviceLockOnOpen(enabled);
    errorMessage = null;
    notifyListeners();
    return true;
  }

  /// System PIN / pattern / fingerprint / face unlock.
  Future<bool> verifyDeviceLock({
    String reason = 'Unlock PasswordSaver with your device lock',
  }) async {
    final ok = await _biometric.authenticate(reason: reason);
    if (ok) {
      deviceLockVerifiedAt = DateTime.now();
    }
    return ok;
  }

  Future<void> acceptTerms() async {
    termsAccepted = true;
    await _storage.write('terms_accepted', 'true');
    notifyListeners();
  }

  /// Ensures PIN exists before first credential add (requirement 10).
  Future<bool> ensurePinBeforeAdd() async {
    hasPin = await _pin.hasPin();
    notifyListeners();
    return hasPin;
  }

  /// Always requires app PIN before revealing a password.
  Future<bool> confirmViewAccess({String? pin}) async {
    hasPin = await _pin.hasPin();
    if (!hasPin) return false;
    if (pin == null || pin.isEmpty) return false;
    return _pin.verifyPin(pin);
  }

  /// Pulls / pushes Hive ↔ Firebase when online.
  Future<bool> syncNow({bool silent = false}) async {
    if (user == null) {
      if (!silent) {
        errorMessage = 'Sign in required to sync';
        notifyListeners();
      }
      return false;
    }
    final repo = _credentials;
    if (repo is! CredentialRepositoryImpl) return false;

    if (!firebaseReady) {
      if (!silent) {
        errorMessage =
            'Cloud sync is not available right now. Please try again later.';
        notifyListeners();
      }
      return false;
    }

    isSyncing = true;
    errorMessage = null;
    notifyListeners();
    try {
      await syncLocalAttachments(silent: true);
      await repo.syncFromFirebase(user!.uid);
      credentials = await _credentials.getCredentials(user!.uid);
      await syncLocalAttachments(silent: true);
      refreshSyncStatus(notify: false);
      return true;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      refreshSyncStatus(notify: false);
      return false;
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  /// Updates [unsyncedCount] / [lastSyncedAt] from Hive pending queue.
  void refreshSyncStatus({bool notify = true}) {
    if (user == null) {
      unsyncedCount = 0;
      lastSyncedAt = null;
      if (notify) notifyListeners();
      return;
    }
    final repo = _credentials;
    if (repo is! CredentialRepositoryImpl) return;
    unsyncedCount = repo.pendingCount(user!.uid);
    lastSyncedAt = repo.lastSyncAt(user!.uid);
    if (notify) notifyListeners();
  }

  /// On app open: sync automatically if there are pending offline changes
  /// or the vault has never synced to cloud.
  Future<bool> autoSyncIfNeeded() async {
    if (user == null || !firebaseReady) return false;
    if (isSyncing) return false;
    final localPending =
        credentials.any((c) => c.isLocalAttachment);
    await syncLocalAttachments(silent: true);
    refreshSyncStatus(notify: false);
    final needsSync =
        unsyncedCount > 0 || lastSyncedAt == null || localPending;
    if (!needsSync) return false;
    return syncNow(silent: true);
  }

  /// Uploads any on-device attachments that failed Firebase Storage earlier.
  Future<int> syncLocalAttachments({bool silent = false}) async {
    if (user == null || !firebaseReady) return 0;
    var synced = 0;
    final updated = <CredentialEntry>[];
    for (final c in credentials) {
      if (!c.isLocalAttachment) {
        updated.add(c);
        continue;
      }
      var changed = false;
      final nextFiles = <CredentialAttachment>[];
      for (final file in c.effectiveAttachments) {
        if (!file.isLocal || file.path == null) {
          nextFiles.add(file);
          continue;
        }
        final remote = await _attachments.uploadLocalToRemote(
          userId: c.userId,
          credentialId: c.id,
          localStoragePath: file.path!,
          fileName: file.name ?? 'file',
          mimeType: file.mime ?? 'application/octet-stream',
        );
        if (remote == null) {
          nextFiles.add(file);
          continue;
        }
        nextFiles.add(
          file.copyWith(
            url: remote.downloadUrl,
            path: remote.storagePath,
            name: remote.fileName,
            mime: remote.mimeType,
            sizeBytes: remote.sizeBytes,
          ),
        );
        changed = true;
        synced++;
      }
      if (!changed) {
        updated.add(c);
        continue;
      }
      final saved =
          await _credentials.updateCredential(c.withAttachments(nextFiles));
      updated.add(saved);
    }
    if (synced > 0) {
      credentials = updated;
      if (!silent) notifyListeners();
    }
    return synced;
  }

  /// Requires app PIN for delete/update (requirement 13).
  Future<bool> confirmSensitiveAction(String pin) => _pin.verifyPin(pin);

  Future<bool> addCredential({
    required PlatformCategory platform,
    required String title,
    required String accountUserId,
    required String plainPassword,
    String description = '',
    String? website,
    String? customPlatformName,
    String? accountGroup,
    File? attachmentFile,
    List<File>? attachmentFiles,
  }) async {
    return _run(() async {
      if (user == null) throw Exception('Not signed in');
      final masterKey = await _storage.getMasterKey();
      if (masterKey == null) throw Exception('Encryption key missing');

      // First real password → remove all demo Gmail / WhatsApp / etc.
      if (credentials.any((c) => c.isDemoSample)) {
        await _clearDemoSamples();
      }

      final encrypted = _enc.encrypt(plainPassword, masterKey);
      final groupName = StringFormatters.toTitleCase(accountGroup ?? '');

      // Place new account at end of its service + company group
      final sameGroup = credentials.where((c) {
        final sameService = platform == PlatformCategory.other &&
                customPlatformName != null &&
                customPlatformName.trim().isNotEmpty
            ? c.groupKey ==
                'other:${customPlatformName.trim().toLowerCase()}'
            : c.platform == platform;
        if (!sameService) return false;
        return c.accountGroupKey ==
            (groupName.isEmpty ? 'general' : groupName.toLowerCase());
      });
      final nextOrder = sameGroup.isEmpty
          ? 0
          : sameGroup.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) +
              1;

      final credentialId = _uuid.v4();
      final filesToUpload = <File>[
        ...?attachmentFiles,
        ?attachmentFile,
      ];
      if (filesToUpload.length > AppConstants.maxAttachmentsPerCredential) {
        throw Exception(
          'You can attach up to ${AppConstants.maxAttachmentsPerCredential} files per password',
        );
      }
      ensureCanAddAttachment(newFileCount: filesToUpload.length);

      final uploadedAttachments = <CredentialAttachment>[];
      for (final file in filesToUpload) {
        final uploaded = await _attachments.compressAndUpload(
          userId: user!.uid,
          credentialId: credentialId,
          file: file,
        );
        uploadedAttachments.add(
          CredentialAttachment(
            id: _uuid.v4(),
            url: uploaded.downloadUrl,
            path: uploaded.storagePath,
            name: uploaded.fileName,
            mime: uploaded.mimeType,
            sizeBytes: uploaded.sizeBytes,
            createdAt: DateTime.now(),
          ),
        );
      }

      final entry = CredentialEntry(
        id: credentialId,
        userId: user!.uid,
        platform: platform,
        title: title,
        accountUserId: accountUserId,
        encryptedPassword: encrypted,
        description: description,
        website: website,
        customPlatformName: platform == PlatformCategory.other
            ? StringFormatters.toTitleCase(customPlatformName ?? '')
            : null,
        accountGroup: groupName.isEmpty ? null : groupName,
        accountGroupId: AccountGroup.docIdFor(
          serviceKey: platform == PlatformCategory.other &&
                  (customPlatformName ?? '').trim().isNotEmpty
              ? 'other:${customPlatformName!.trim().toLowerCase()}'
              : platform.name,
          groupName: groupName.isEmpty ? 'General' : groupName,
        ),
        sortOrder: nextOrder,
        isDemoSample: false,
        attachments: uploadedAttachments,
        attachmentUrl: uploadedAttachments.isNotEmpty
            ? uploadedAttachments.first.url
            : null,
        attachmentPath: uploadedAttachments.isNotEmpty
            ? uploadedAttachments.first.path
            : null,
        attachmentName: uploadedAttachments.isNotEmpty
            ? uploadedAttachments.first.name
            : null,
        attachmentMime: uploadedAttachments.isNotEmpty
            ? uploadedAttachments.first.mime
            : null,
        attachmentSizeBytes: uploadedAttachments.isNotEmpty
            ? uploadedAttachments.first.sizeBytes
            : null,
      );
      final saved = await _credentials.addCredential(entry);
      credentials = [...credentials, saved];
      await _storage.write('demo_samples_cleared', 'true');
      refreshSyncStatus(notify: false);
    });
  }

  Future<bool> updateCredential({
    required CredentialEntry entry,
    required String plainPassword,
    File? attachmentFile,
    List<File>? attachmentFiles,
    bool removeAttachment = false,
    List<String>? removeAttachmentIds,
  }) async {
    return _run(() async {
      final masterKey = await _storage.getMasterKey();
      if (masterKey == null) throw Exception('Encryption key missing');
      final encrypted = _enc.encrypt(plainPassword, masterKey);

      var next = entry.copyWith(encryptedPassword: encrypted);
      var files = List<CredentialAttachment>.from(entry.effectiveAttachments);

      Future<void> deletePath(String? path) async {
        if (path == null || path.isEmpty) return;
        final repo = _credentials;
        if (repo is CredentialRepositoryImpl) {
          await repo.deleteAttachmentReliably(
            userId: entry.userId,
            credentialId: entry.id,
            attachmentPath: path,
          );
        } else {
          await _attachments.deleteIfExists(path);
        }
      }

      if (removeAttachment) {
        for (final f in files) {
          await deletePath(f.path);
        }
        files = [];
      } else if (removeAttachmentIds != null &&
          removeAttachmentIds.isNotEmpty) {
        final remove = removeAttachmentIds.toSet();
        final keep = <CredentialAttachment>[];
        for (final f in files) {
          if (remove.contains(f.id)) {
            await deletePath(f.path);
          } else {
            keep.add(f);
          }
        }
        files = keep;
      }

      final filesToUpload = <File>[
        ...?attachmentFiles,
        ?attachmentFile,
      ];
      if (files.length + filesToUpload.length >
          AppConstants.maxAttachmentsPerCredential) {
        throw Exception(
          'You can attach up to ${AppConstants.maxAttachmentsPerCredential} files per password',
        );
      }
      ensureCanAddAttachment(newFileCount: filesToUpload.length);

      for (final file in filesToUpload) {
        final uploaded = await _attachments.compressAndUpload(
          userId: entry.userId,
          credentialId: entry.id,
          file: file,
        );
        files.add(
          CredentialAttachment(
            id: _uuid.v4(),
            url: uploaded.downloadUrl,
            path: uploaded.storagePath,
            name: uploaded.fileName,
            mime: uploaded.mimeType,
            sizeBytes: uploaded.sizeBytes,
            createdAt: DateTime.now(),
          ),
        );
      }

      next = next.withAttachments(files);

      final updated = await _credentials.updateCredential(next);
      credentials =
          credentials.map((c) => c.id == updated.id ? updated : c).toList();
      refreshSyncStatus(notify: false);
    });
  }

  /// Persists a new account order after drag-reorder.
  Future<void> reorderCredentials(List<CredentialEntry> ordered) async {
    final updatedList = <CredentialEntry>[];
    for (var i = 0; i < ordered.length; i++) {
      final entry = ordered[i].copyWith(sortOrder: i);
      final saved = await _credentials.updateCredential(entry);
      updatedList.add(saved);
    }
    final byId = {for (final e in updatedList) e.id: e};
    credentials = credentials.map((c) => byId[c.id] ?? c).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    refreshSyncStatus();
  }

  Future<bool> deleteCredential(String id, String pin) async {
    return _run(() async {
      if (user == null) throw Exception('Not signed in');
      final ok = await confirmSensitiveAction(pin);
      if (!ok) throw Exception('Incorrect app PIN');
      final existing = credentials.where((c) => c.id == id).firstOrNull;
      final paths = existing?.effectiveAttachments
              .map((a) => a.path)
              .whereType<String>()
              .where((p) => p.isNotEmpty)
              .toList() ??
          const <String>[];
      await _credentials.deleteCredential(
        user!.uid,
        id,
        attachmentPath: paths.isNotEmpty ? paths.first : existing?.attachmentPath,
        attachmentPaths: paths,
      );
      credentials = credentials.where((c) => c.id != id).toList();
      refreshSyncStatus(notify: false);
    });
  }

  /// Opens attachment from app cache when possible; otherwise downloads once,
  /// stores it under app documents, and retries on network failure.
  Future<File> downloadAttachment(
    CredentialEntry entry, [
    CredentialAttachment? file,
  ]) async {
    final target = file ??
        (entry.effectiveAttachments.isNotEmpty
            ? entry.effectiveAttachments.first
            : null);
    if (target == null) {
      throw Exception('No attachment on this entry');
    }
    if (!canOpenAttachment(entry, target)) {
      final months = user?.subscriptionPlanMonths;
      final filePlan = subscriptionCatalog.fileUpgradeForMonths(months);
      throw FilePlanRenewalRequiredException(
        months: months ?? filePlan?.months ?? 3,
        priceInr: filePlan?.priceInr ?? 0,
        extraFiles: filePlan?.maxAttachmentFiles ?? 0,
      );
    }
    return _attachments.resolveAttachmentFile(
      userId: entry.userId,
      credentialId: entry.id,
      storagePath: target.path,
      downloadUrl: target.url,
      fileName: target.name ??
          AttachmentStorageService.fileNameFromStoragePath(target.path) ??
          'attachment',
    );
  }

  /// True when the file is already on device (local or cache) — no Firebase needed.
  Future<bool> isAttachmentCached(
    CredentialEntry entry, [
    CredentialAttachment? file,
  ]) {
    final target = file ??
        (entry.effectiveAttachments.isNotEmpty
            ? entry.effectiveAttachments.first
            : null);
    if (target == null) return Future.value(false);
    return _attachments.hasCachedFile(
      userId: entry.userId,
      credentialId: entry.id,
      storagePath: target.path,
      fileName: target.name ?? 'attachment',
    );
  }

  String? decryptPassword(CredentialEntry entry) {
    try {
      // Synchronous decrypt needs key — caller should use decryptPasswordAsync
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> decryptPasswordAsync(CredentialEntry entry) async {
    final masterKey = await _storage.getMasterKey();
    if (masterKey == null) {
      throw Exception(
        'Encryption key missing. Sign out and sign in again to unlock the vault.',
      );
    }
    final payload = entry.encryptedPassword.trim();
    if (payload.isEmpty) {
      throw Exception('No password is stored for this entry.');
    }
    try {
      return _enc.decrypt(payload, masterKey);
    } on EncryptionException {
      throw Exception(
        'Could not decrypt this password. It may have been saved under an '
        'old vault key (for example after account password reset). '
        'Edit this entry and save the password again.',
      );
    }
  }

  /// Creates Razorpay order + verifies payment via Cloud Function, then refreshes plan.
  /// Activation is written by the server (Admin SDK) — client cannot fake it.
  Future<bool> confirmRazorpaySubscription({
    required int months,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    String planType = 'subscription',
  }) async {
    return _run(() async {
      if (user == null) throw Exception('Not signed in');
      final cloud = RazorpayCloudFunctions();
      final verified = await cloud.verifyPayment(
        razorpayOrderId: razorpayOrderId,
        razorpayPaymentId: razorpayPaymentId,
        razorpaySignature: razorpaySignature,
        months: months,
        planType: planType,
      );
      if (!verified.ok) {
        throw Exception('Payment verification failed');
      }
      await refreshSubscriptionFromFirebase();
      await refreshUserProfile();
    });
  }

  /// Creates a server-side Razorpay order for [months].
  Future<RazorpayOrderResult> createRazorpayOrder(
    int months, {
    String planType = 'subscription',
    bool includeFilePlan = false,
    String? buyerGstin,
  }) {
    return RazorpayCloudFunctions().createOrder(
      months: months,
      planType: planType,
      includeFilePlan: includeFilePlan,
      buyerGstin: buyerGstin,
    );
  }

  /// Activates or upgrades a paid plan after payment confirmation.
  ///
  /// Prefer [confirmRazorpaySubscription] (Cloud Function verify).
  /// This local path remains for admin / legacy use only.
  Future<bool> activateSubscription(
    int months, {
    required num paidAmount,
    bool paidInUsd = false,
    String? razorpayPaymentId,
    String? razorpayOrderId,
    String? razorpaySignature,
  }) async {
    return _run(() async {
      if (user == null) throw Exception('Not signed in');

      final currentPlan = user!.subscriptionPlanMonths;
      final isSame =
          user!.hasPaidPlan && currentPlan == months;
      final isDowngrade = user!.hasPaidPlan &&
          currentPlan != null &&
          months < currentPlan;

      if (isSame) {
        throw Exception('You are already on this plan');
      }
      if (isDowngrade) {
        throw Exception('Select a higher plan to upgrade');
      }

      final catalogPrice = AppConstants.subscriptionPlans[months] ?? 100;
      final catalogUsd = subscriptionCatalog.usdFromInr(catalogPrice);
      if (!SubscriptionPricing.amountsMatch(
        paidAmount: paidAmount,
        catalogInr: catalogPrice,
        catalogUsd: catalogUsd,
        paidInUsd: paidInUsd,
        gst: subscriptionCatalog.gst,
      )) {
        throw Exception('Payment amount mismatch');
      }

      final now = DateTime.now();
      // Upgrade/renew replaces the base plan — leftover days are not carried over.
      final expiry = DateTime(now.year, now.month + months, now.day);

      await _subscription.activatePlan(
        userId: user!.uid,
        months: months,
        priceInr: catalogPrice,
        expiresAt: expiry,
        razorpayPaymentId: razorpayPaymentId,
        razorpayOrderId: razorpayOrderId,
        razorpaySignature: razorpaySignature,
      );

      user = user!.copyWith(
        subscriptionExpiresAt: expiry,
        lastExpiresAt: expiry,
        isTrialActive: false,
        subscriptionPlanMonths: months,
      );
      await _auth.updateProfile(user!);
    });
  }

  /// Short invite code derived from the signed-in user (share with friends).
  String get inviteCode {
    final raw = (user?.userId ?? user?.uid ?? 'GUEST').toUpperCase();
    final cleaned = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final base = (cleaned.isEmpty ? 'USER' : cleaned)
        .padRight(4, 'X')
        .substring(0, 4);
    final hash = ((user?.uid.hashCode.abs() ?? 0) % 10000)
        .toString()
        .padLeft(4, '0');
    return 'PS$base$hash';
  }

  /// Share text: install link + invite code.
  String buildInviteShareMessage() {
    return '''
Join me on ${AppConstants.appName} — encrypted password vault!

Install the app and enter my invite code so I can unlock a free month:

Invite code: $inviteCode

Install Android app:
${AppConstants.playStoreUrl}

Stay safe. Share passwords with nobody — store them encrypted.
'''.trim();
  }

  /// Extends subscription / trial by [months] from the later of now or current expiry.
  Future<void> _extendSubscriptionByMonths(int months) async {
    if (user == null) return;
    final now = DateTime.now();
    final current = user!.subscriptionExpiresAt;
    final base = (current != null && current.isAfter(now)) ? current : now;
    final expiry = DateTime(base.year, base.month + months, base.day);
    user = user!.copyWith(
      subscriptionExpiresAt: expiry,
      lastExpiresAt: expiry,
      isTrialActive: user!.isTrialActive,
    );
    if (_subscription case final SubscriptionRepositoryImpl repo) {
      await repo.extendAccess(
        userId: user!.uid,
        expiresAt: expiry,
        isTrialActive: user!.isTrialActive,
        planMonths: user!.subscriptionPlanMonths,
      );
    }
    await _auth.updateProfile(user!);
  }

  Future<void> _persistInvitePoints() async {
    await _storage.write(
      AppConstants.keyInvitePoints,
      invitePoints.toString(),
    );
  }

  /// Hive key for installs registered against an invite code.
  String _inviteInstallsKey(String code) => 'invite_installs_$code';

  /// Share action: +50 points only (no free month).
  Future<bool> rewardInviteSharePoints() async {
    if (!AppConstants.inviteFriendsEnabled) return false;
    if (user == null) {
      errorMessage = 'Sign in to earn invite points';
      notifyListeners();
      return false;
    }

    inviteSentCount += 1;
    await _storage.write(
      AppConstants.keyInviteSentCount,
      inviteSentCount.toString(),
    );

    invitePoints += AppConstants.inviteSharePoints;
    await _persistInvitePoints();
    errorMessage = null;
    notifyListeners();
    return true;
  }

  /// Redeem 200 points → +1 month free.
  Future<bool> redeemInvitePointsForMonth() async {
    if (!AppConstants.inviteFriendsEnabled) return false;
    return _run(() async {
      if (user == null) throw Exception('Sign in required');
      if (invitePoints < AppConstants.invitePointsPerMonth) {
        throw Exception(
          'Need ${AppConstants.invitePointsPerMonth} points '
          '(you have $invitePoints)',
        );
      }
      invitePoints -= AppConstants.invitePointsPerMonth;
      await _persistInvitePoints();
      await _extendSubscriptionByMonths(AppConstants.inviteBonusMonths);
    });
  }

  /// Friend installs + enters your code → registers install for the inviter.
  /// Inviter gets +1 month when they sync install rewards (not the friend).
  Future<bool> claimInviteCode(String code) async {
    if (!AppConstants.inviteFriendsEnabled) return false;
    return _run(() async {
      if (user == null) throw Exception('Sign in required');
      if (inviteCodeClaimed) {
        throw Exception('You already registered an invite install');
      }

      final cleaned = code.trim().toUpperCase().replaceAll(' ', '');
      if (cleaned.length < 6) {
        throw Exception('Enter a valid invite code');
      }
      if (cleaned == inviteCode) {
        throw Exception('You cannot use your own invite code');
      }
      if (!cleaned.startsWith('PS')) {
        throw Exception('Invalid invite code format');
      }

      // Register this install against the friend's invite code (local registry)
      final key = _inviteInstallsKey(cleaned);
      final raw = HiveBoxes.syncMetaBox.get(key);
      final list = <String>[];
      if (raw is List) {
        list.addAll(raw.map((e) => e.toString()));
      }
      if (list.contains(user!.uid)) {
        throw Exception('Install already registered for this code');
      }
      list.add(user!.uid);
      await HiveBoxes.syncMetaBox.put(key, list);

      inviteCodeClaimed = true;
      await _storage.write(AppConstants.keyInviteCodeClaimed, 'true');
    });
  }

  /// Grants +1 month for each new friend install on this user's invite code.
  Future<int> syncInviteInstallRewards() async {
    if (!AppConstants.inviteFriendsEnabled) return 0;
    if (user == null) return 0;

    final key = _inviteInstallsKey(inviteCode);
    final raw = HiveBoxes.syncMetaBox.get(key);
    final installs = raw is List ? raw.length : 0;
    final pending = installs - inviteInstallRewardsClaimed;
    if (pending <= 0) return 0;

    for (var i = 0; i < pending; i++) {
      await _extendSubscriptionByMonths(AppConstants.inviteBonusMonths);
    }
    inviteInstallRewardsClaimed = installs;
    await _storage.write(
      AppConstants.keyInviteInstallRewardsClaimed,
      inviteInstallRewardsClaimed.toString(),
    );
    notifyListeners();
    return pending;
  }

  /// How many friend installs are registered for this invite code.
  int get inviteInstallCount {
    final raw = HiveBoxes.syncMetaBox.get(_inviteInstallsKey(inviteCode));
    return raw is List ? raw.length : 0;
  }

  /// Reloads admin-controlled plan pricing + file limits.
  Future<void> refreshSubscriptionCatalog({bool notify = true}) async {
    try {
      subscriptionCatalog = await _catalogService.load();
    } catch (_) {
      subscriptionCatalog = SubscriptionCatalog.defaults();
    }
    if (notify) notifyListeners();
  }

  /// Throws [FileLimitReachedException] when new files would exceed quota.
  void ensureCanAddAttachment({
    bool consumesNewSlot = false,
    int newFileCount = 0,
  }) {
    final count = newFileCount > 0 ? newFileCount : (consumesNewSlot ? 1 : 0);
    if (count <= 0) return;
    if (canAddAttachments(count)) return;
    throw FileLimitReachedException(
      used: attachmentFileCount,
      limit: attachmentFileLimit,
    );
  }

  Future<void> refreshCredentials() async {
    if (user == null) return;
    credentials = await _credentials.getCredentials(user!.uid);
    notifyListeners();
  }

  /// Updates name + recovery mobile / recovery email.
  /// Changing a value clears its verified flag until OTP succeeds.
  Future<bool> updateUserProfile({
    required String displayName,
    String? recoveryMobile,
    String? recoveryEmail,
  }) async {
    return _run(() async {
      if (user == null) throw Exception('Not signed in');
      final name = displayName.trim();
      if (name.length < 2) throw Exception('Enter a valid name');

      final mobile = (recoveryMobile ?? '').trim();
      final email = (recoveryEmail ?? '').trim();

      final oldMobile = (user!.primaryMobile ?? '').trim();
      final oldEmail = (user!.recoveryEmail ?? '').trim();

      var next = user!.copyWith(
        displayName: name,
        primaryMobile: mobile.isEmpty ? '' : mobile,
        secondaryMobile: email.isEmpty ? '' : email,
      );

      // copyWith can't clear with null — write empty string then normalize
      if (mobile != oldMobile) {
        next = next.copyWith(primaryMobileVerified: false);
      }
      if (email != oldEmail) {
        next = next.copyWith(recoveryEmailVerified: false);
      }
      if (mobile.isEmpty) {
        next = next.copyWith(primaryMobileVerified: false);
      }
      if (email.isEmpty) {
        next = next.copyWith(recoveryEmailVerified: false);
      }

      // Persist empty as null-ish empty string in map is fine; normalize empties
      final toSave = AppUser(
        uid: next.uid,
        email: next.email,
        displayName: next.displayName,
        userId: next.userId,
        primaryMobile: mobile.isEmpty ? null : mobile,
        secondaryMobile: email.isEmpty ? null : email,
        photoUrl: next.photoUrl,
        deviceDetails: next.deviceDetails,
        emailVerified: next.emailVerified,
        primaryMobileVerified:
            mobile.isEmpty ? false : next.primaryMobileVerified,
        recoveryEmailVerified:
            email.isEmpty ? false : next.recoveryEmailVerified,
        createdAt: next.createdAt,
        trialStartedAt: next.trialStartedAt,
        subscriptionExpiresAt: next.subscriptionExpiresAt,
        lastExpiresAt: next.lastExpiresAt,
        isTrialActive: next.isTrialActive,
        subscriptionPlanMonths: next.subscriptionPlanMonths,
        isLifetimeFree: next.isLifetimeFree,
        filePlanMonths: next.filePlanMonths,
        filePlanMaxFiles: next.filePlanMaxFiles,
        filePlanExpiresAt: next.filePlanExpiresAt,
        isBlocked: next.isBlocked,
        countryCode: next.countryCode,
        countryName: next.countryName,
      );

      await _auth.updateProfile(toSave);
      user = toSave;
    });
  }

  /// Reloads profile from Firestore (after OTP verify).
  Future<void> refreshUserProfile() async {
    final loaded = await _auth.reloadCurrentUser();
    if (loaded != null) {
      user = loaded;
      notifyListeners();
    }
  }

  /// Saves country via Cloud Function, then reloads profile from backend.
  Future<bool> saveUserCountry({
    required String countryCode,
    required String countryName,
  }) async {
    return _run(() async {
      final result = await _userCloud.setUserCountry(
        countryCode: countryCode,
        countryName: countryName,
      );
      if (!result.ok) {
        throw Exception('Country could not be saved');
      }
      await refreshUserProfile();
      if (user?.hasSelectedCountry != true) {
        throw Exception('Country was not verified on the server');
      }
    });
  }

  Future<bool> _run(Future<void> Function() action) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

/// Thrown when vault attachment quota is exhausted.
class FileLimitReachedException implements Exception {
  FileLimitReachedException({required this.used, required this.limit});

  final int used;
  final int limit;

  @override
  String toString() =>
      'File limit reached ($used/$limit). Upgrade your plan for more files.';
}

/// Thrown when opening an add-on file without an active file plan.
class FilePlanRenewalRequiredException implements Exception {
  FilePlanRenewalRequiredException({
    required this.months,
    required this.priceInr,
    required this.extraFiles,
  });

  final int months;
  final int priceInr;
  final int extraFiles;

  @override
  String toString() =>
      'Renew your $months-month file plan to open this file.';
}











