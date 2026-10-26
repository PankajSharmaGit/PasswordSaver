import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/app_constants.dart';
import '../../core/security/encryption_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../domain/repositories/repositories.dart';

/// App PIN repository — local secure storage + Firebase sync (hash only).
class PinRepositoryImpl implements PinRepository {
  PinRepositoryImpl({
    required SecureStorageService storage,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _storage = storage,
        _auth = auth,
        _firestore = firestore;

  final SecureStorageService _storage;
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final _enc = EncryptionService.instance;

  String? get _uid => _auth?.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? _userDoc(String uid) {
    final fs = _firestore;
    if (fs == null) return null;
    return fs.collection(AppConstants.colUsers).doc(uid);
  }

  @override
  Future<bool> hasPin() async {
    if (await _storage.hasAppPin()) return true;
    await syncFromFirebase();
    return _storage.hasAppPin();
  }

  @override
  Future<void> createPin(String pin) async {
    _validatePin(pin);
    final salt = await _resolvePinSalt(createIfMissing: true);
    final hash = _enc.hashPin(pin, salt!);
    await _storage.write(AppConstants.keyAppPinSalt, salt);
    await _storage.write(AppConstants.keyAppPinHash, hash);
    await _pushToFirebase(salt: salt, hash: hash);
  }

  @override
  Future<bool> verifyPin(String pin) async {
    if (!await _storage.hasAppPin()) {
      await syncFromFirebase();
    }
    final salt = await _resolvePinSalt(createIfMissing: false);
    final hash = await _storage.read(AppConstants.keyAppPinHash);
    if (salt == null || hash == null) return false;
    return _enc.verifyPin(pin, salt, hash);
  }

  /// Prefers dedicated PIN salt; migrates legacy encryption_salt if needed.
  Future<String?> _resolvePinSalt({required bool createIfMissing}) async {
    var salt = await _storage.read(AppConstants.keyAppPinSalt);
    if (salt != null && salt.isNotEmpty) return salt;

    // Legacy: PIN used to share encryption_salt.
    final legacy = await _storage.read(AppConstants.keyEncryptionSalt);
    if (legacy != null && legacy.isNotEmpty) {
      await _storage.write(AppConstants.keyAppPinSalt, legacy);
      return legacy;
    }

    if (!createIfMissing) return null;
    salt = _enc.generateSalt();
    await _storage.write(AppConstants.keyAppPinSalt, salt);
    return salt;
  }

  @override
  Future<bool> updatePin({
    required String oldPin,
    required String newPin,
  }) async {
    final ok = await verifyPin(oldPin);
    if (!ok) return false;
    _validatePin(newPin);
    await createPin(newPin);
    return true;
  }

  @override
  Future<void> resetPin(String newPin) async {
    _validatePin(newPin);
    await createPin(newPin);
  }

  /// Pulls PIN hash/salt from Firestore into local secure storage (new device).
  Future<void> syncFromFirebase() async {
    final uid = _uid;
    final doc = uid == null ? null : _userDoc(uid);
    if (doc == null) return;
    try {
      final snap = await doc.get();
      final data = snap.data();
      if (data == null) return;
      final hash = data[AppConstants.fieldAppPinHash]?.toString();
      final salt = data[AppConstants.fieldAppPinSalt]?.toString();
      if (hash == null ||
          hash.isEmpty ||
          salt == null ||
          salt.isEmpty) {
        // Local PIN exists but never synced — push now.
        await pushLocalPinToFirebaseIfNeeded();
        return;
      }
      await _storage.write(AppConstants.keyAppPinHash, hash);
      await _storage.write(AppConstants.keyAppPinSalt, salt);
    } catch (_) {
      // Offline / permission — keep local state.
    }
  }

  /// Uploads an existing on-device PIN to Firestore (one-time migrate).
  Future<void> pushLocalPinToFirebaseIfNeeded() async {
    final uid = _uid;
    final doc = uid == null ? null : _userDoc(uid);
    if (doc == null) return;
    final hash = await _storage.read(AppConstants.keyAppPinHash);
    final salt = await _resolvePinSalt(createIfMissing: false);
    if (hash == null || hash.isEmpty || salt == null || salt.isEmpty) return;
    try {
      final snap = await doc.get();
      final remote = snap.data()?[AppConstants.fieldAppPinHash]?.toString();
      if (remote != null && remote.isNotEmpty) return;
      await _pushToFirebase(salt: salt, hash: hash);
    } catch (_) {}
  }

  Future<void> _pushToFirebase({
    required String salt,
    required String hash,
  }) async {
    final uid = _uid;
    final doc = uid == null ? null : _userDoc(uid);
    if (doc == null) return;
    try {
      await doc.set({
        AppConstants.fieldAppPinHash: hash,
        AppConstants.fieldAppPinSalt: salt,
        AppConstants.fieldAppPinUpdatedAt: DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('PIN saved on device but Firebase sync failed: $e');
    }
  }

  void _validatePin(String pin) {
    if (!RegExp('^\\d{${AppConstants.appPinLength}}\$').hasMatch(pin)) {
      throw Exception('App PIN must be ${AppConstants.appPinLength} digits');
    }
  }
}

/// Snapshot of trial / paid access from Firestore.
class SubscriptionStatus {
  const SubscriptionStatus({
    required this.expiresAt,
    required this.isTrialActive,
    this.planMonths,
    this.trialStartedAt,
    this.lastExpiresAt,
    this.isLifetimeFree = false,
  });

  final DateTime? expiresAt;
  final bool isTrialActive;
  final int? planMonths;
  final DateTime? trialStartedAt;
  final DateTime? lastExpiresAt;
  final bool isLifetimeFree;
}

/// Subscription plan activation + cloud sync (trial / paid).
class SubscriptionRepositoryImpl implements SubscriptionRepository {
  SubscriptionRepositoryImpl({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _subDoc(String userId) =>
      _firestore.collection(AppConstants.colSubscriptions).doc(userId);

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) =>
      _firestore.collection(AppConstants.colUsers).doc(userId);

  /// Writes free-trial record (users + subscriptions) for a new account.
  Future<void> saveTrial({
    required String userId,
    required DateTime startedAt,
    required DateTime expiresAt,
  }) async {
    final payload = {
      'userId': userId,
      'type': 'trial',
      'months': null,
      'priceInr': 0,
      'activatedAt': startedAt.toIso8601String(),
      'trialStartedAt': startedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'lastExpiresAt': expiresAt.toIso8601String(),
      'subscriptionPlan': 'trial',
    };
    await _subDoc(userId).set(payload, SetOptions(merge: true));
    await _userDoc(userId).set({
      'trialStartedAt': startedAt.toIso8601String(),
      'subscriptionExpiresAt': expiresAt.toIso8601String(),
      'lastExpiresAt': expiresAt.toIso8601String(),
      'isTrialActive': true,
      'subscriptionPlanMonths': FieldValue.delete(),
      'subscriptionPlan': 'trial',
    }, SetOptions(merge: true));
  }

  /// Reads the effective plan from `subscriptions/{uid}` (preferred) + user doc.
  Future<SubscriptionStatus> fetchStatus(String userId) async {
    final subSnap = await _subDoc(userId).get();
    final userSnap = await _userDoc(userId).get();
    final sub = subSnap.data();
    final user = userSnap.data();

    DateTime? parseDate(dynamic raw) =>
        raw == null ? null : DateTime.tryParse(raw.toString());

    final lifetimeFromUser = user?['isLifetimeFree'] == true;
    final lifetimeFromSub = sub != null &&
        (sub['isLifetimeFree'] == true ||
            sub['type']?.toString() == 'lifetime_free' ||
            sub['subscriptionPlan']?.toString() == 'lifetime_free');
    if (lifetimeFromUser || lifetimeFromSub) {
      return SubscriptionStatus(
        expiresAt: null,
        lastExpiresAt: null,
        trialStartedAt: parseDate(user?['trialStartedAt']) ??
            parseDate(user?['createdAt']),
        isTrialActive: false,
        planMonths: null,
        isLifetimeFree: true,
      );
    }

    if (sub != null && sub.isNotEmpty) {
      final type = sub['type']?.toString() ?? '';
      final monthsRaw = sub['months'];
      final months = monthsRaw is int
          ? monthsRaw
          : int.tryParse('${monthsRaw ?? ''}');
      final expires = parseDate(sub['expiresAt']) ??
          parseDate(sub['lastExpiresAt']) ??
          parseDate(user?['subscriptionExpiresAt']) ??
          parseDate(user?['lastExpiresAt']);
      final trialStart = parseDate(sub['trialStartedAt']) ??
          parseDate(sub['activatedAt']) ??
          parseDate(user?['trialStartedAt']) ??
          parseDate(user?['createdAt']);
      final isTrial = type == 'trial' ||
          (months == null && (user?['isTrialActive'] as bool? ?? true));
      return SubscriptionStatus(
        expiresAt: expires,
        lastExpiresAt: parseDate(sub['lastExpiresAt']) ?? expires,
        trialStartedAt: trialStart,
        isTrialActive: isTrial,
        planMonths: isTrial ? null : months,
        isLifetimeFree: false,
      );
    }

    if (user != null) {
      final monthsRaw = user['subscriptionPlanMonths'];
      final months = monthsRaw is int
          ? monthsRaw
          : int.tryParse('${monthsRaw ?? ''}');
      final isTrial = user['isTrialActive'] as bool? ?? (months == null);
      final expires = parseDate(user['subscriptionExpiresAt']) ??
          parseDate(user['lastExpiresAt']);
      return SubscriptionStatus(
        expiresAt: expires,
        lastExpiresAt: parseDate(user['lastExpiresAt']) ?? expires,
        trialStartedAt:
            parseDate(user['trialStartedAt']) ?? parseDate(user['createdAt']),
        isTrialActive: isTrial,
        planMonths: isTrial ? null : months,
        isLifetimeFree: false,
      );
    }

    return const SubscriptionStatus(
      expiresAt: null,
      isTrialActive: true,
      planMonths: null,
      isLifetimeFree: false,
    );
  }

  @override
  Future<void> activatePlan({
    required String userId,
    required int months,
    required int priceInr,
    DateTime? expiresAt,
    String? razorpayPaymentId,
    String? razorpayOrderId,
    String? razorpaySignature,
  }) async {
    final now = DateTime.now();
    final expiry =
        expiresAt ?? DateTime(now.year, now.month + months, now.day);
    final payload = {
      'userId': userId,
      'type': 'paid',
      'months': months,
      'priceInr': priceInr,
      'activatedAt': now.toIso8601String(),
      'expiresAt': expiry.toIso8601String(),
      'lastExpiresAt': expiry.toIso8601String(),
      'subscriptionPlan': '${months}_month',
      'isLifetimeFree': false,
      if (razorpayPaymentId != null) 'razorpayPaymentId': razorpayPaymentId,
      if (razorpayOrderId != null) 'razorpayOrderId': razorpayOrderId,
      if (razorpaySignature != null) 'razorpaySignature': razorpaySignature,
      'paymentGateway': 'razorpay',
    };

    await _subDoc(userId).set(payload, SetOptions(merge: true));
    await _userDoc(userId).set({
      'subscriptionExpiresAt': expiry.toIso8601String(),
      'lastExpiresAt': expiry.toIso8601String(),
      'isTrialActive': false,
      'isLifetimeFree': false,
      'subscriptionPlanMonths': months,
      'subscriptionPlan': '${months}_month',
      if (razorpayPaymentId != null) 'razorpayPaymentId': razorpayPaymentId,
      'paymentGateway': 'razorpay',
    }, SetOptions(merge: true));
  }

  /// Extends current expiry (invite rewards, etc.) and syncs both collections.
  Future<void> extendAccess({
    required String userId,
    required DateTime expiresAt,
    required bool isTrialActive,
    int? planMonths,
  }) async {
    final payload = <String, dynamic>{
      'userId': userId,
      'type': isTrialActive ? 'trial' : 'paid',
      'expiresAt': expiresAt.toIso8601String(),
      'lastExpiresAt': expiresAt.toIso8601String(),
      'extendedAt': DateTime.now().toIso8601String(),
    };
    if (!isTrialActive && planMonths != null) {
      payload['months'] = planMonths;
      payload['subscriptionPlan'] = '${planMonths}_month';
    }
    await _subDoc(userId).set(payload, SetOptions(merge: true));
    await _userDoc(userId).set({
      'subscriptionExpiresAt': expiresAt.toIso8601String(),
      'lastExpiresAt': expiresAt.toIso8601String(),
      'isTrialActive': isTrialActive,
      if (planMonths != null) 'subscriptionPlanMonths': planMonths,
    }, SetOptions(merge: true));
  }

  @override
  Future<DateTime?> getExpiry(String userId) async {
    final status = await fetchStatus(userId);
    return status.expiresAt ?? status.lastExpiresAt;
  }

  @override
  Future<int?> getPlanMonths(String userId) async {
    final status = await fetchStatus(userId);
    return status.planMonths;
  }
}

