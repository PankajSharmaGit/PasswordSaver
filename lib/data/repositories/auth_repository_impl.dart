import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/constants/app_constants.dart';
import '../../core/security/encryption_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';

/// True when Firebase was initialized successfully.
class FirebaseAvailability {
  static bool isAvailable = false;
}

/// Firebase-backed auth (email / Google). Local demo login is not supported.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required SecureStorageService storage,
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    GoogleSignIn? googleSignIn,
  })  : _storage = storage,
        _auth = auth,
        _firestore = firestore,
        _googleSignIn =
            googleSignIn ?? GoogleSignIn(scopes: ['email', 'profile']);

  final SecureStorageService _storage;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;

  void _requireFirebase() {
    if (!FirebaseAvailability.isAvailable) {
      throw AuthFailure(
        'Cloud services are unavailable. Please try again later.',
      );
    }
  }

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> get authStateChanges async* {
    yield _current;
    yield* _controller.stream;
  }

  Future<void> _touchLastActive(String uid) async {
    try {
      await _firestore.collection(AppConstants.colUsers).doc(uid).set(
        {'lastActiveAt': DateTime.now().toIso8601String()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> bootstrap() async {
    try {
      _requireFirebase();
      final fbUser = _auth.currentUser;
      if (fbUser != null) {
        _current = await _loadUserDoc(fbUser.uid);
        if (_current != null) {
          await _syncMasterKey(_current!.uid);
          await _touchLastActive(_current!.uid);
        }
        _controller.add(_current);
        return;
      }
      _current = null;
      _controller.add(null);
    } catch (e) {
      if (e is AuthFailure) {
        try {
          await _googleSignIn.signOut();
          await _auth.signOut();
        } catch (_) {}
        await _storage.delete(AppConstants.keyMasterKey);
        _current = null;
        _controller.add(null);
        rethrow;
      }
      _current = null;
      _controller.add(null);
    }
  }

  @override
  Future<AppUser> signUp({
    required String displayName,
    required String userId,
    required String email,
    required String password,
    required String primaryMobile,
    String? secondaryMobile,
    required Map<String, String> deviceDetails,
  }) async {
    _requireFirebase();
    _validateEmail(email);
    _validatePassword(password);
    if (displayName.trim().isEmpty) {
      throw AuthFailure('Display name is required');
    }
    if (userId.trim().length < 3) {
      throw AuthFailure('User ID must be at least 3 characters');
    }
    if (primaryMobile.trim().length < 10) {
      throw AuthFailure('Valid primary mobile is required');
    }

    final now = DateTime.now();
    final trialEnd = AppConstants.trialEndsAt(now);

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user?.updateDisplayName(displayName.trim());
      await cred.user?.sendEmailVerification();

      final user = AppUser(
        uid: cred.user!.uid,
        email: email.trim(),
        displayName: displayName.trim(),
        userId: userId.trim(),
        primaryMobile: primaryMobile.trim(),
        secondaryMobile: secondaryMobile?.trim(),
        deviceDetails: deviceDetails,
        emailVerified: false,
        createdAt: now,
        trialStartedAt: now,
        subscriptionExpiresAt: trialEnd,
        lastExpiresAt: trialEnd,
        isTrialActive: true,
      );
      await _firestore.collection(AppConstants.colUsers).doc(user.uid).set({
        ...user.toMap(),
        'lastActiveAt': now.toIso8601String(),
      });
      await _syncMasterKey(user.uid, wrapSecret: password);
      _setCurrent(user);
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
    required Map<String, String> deviceDetails,
  }) async {
    _requireFirebase();
    _validateEmail(email);
    _validatePassword(password);

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      var user = await _loadUserDoc(cred.user!.uid);
      user ??= AppUser(
        uid: cred.user!.uid,
        email: email.trim(),
        displayName: cred.user!.displayName ?? 'User',
        userId: email.split('@').first,
        deviceDetails: deviceDetails,
        emailVerified: cred.user!.emailVerified,
        createdAt: DateTime.now(),
      );
      user = user.copyWith(deviceDetails: deviceDetails);
      if (user.isBlocked && !AppConstants.isAdminEmail(user.email)) {
        await _auth.signOut();
        throw AuthFailure('This account has been blocked by admin');
      }
      await _firestore.collection(AppConstants.colUsers).doc(user.uid).set(
        {
          ...user.toMap(),
          'lastActiveAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
      await _syncMasterKey(user.uid, wrapSecret: password);
      _setCurrent(user);
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  @override
  Future<AppUser> signInWithGoogle({
    required Map<String, String> deviceDetails,
  }) async {
    _requireFirebase();
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw AuthFailure('Google sign-in cancelled');
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred = await _auth.signInWithCredential(credential);
      final now = DateTime.now();
      var user = await _loadUserDoc(cred.user!.uid);
      user ??= AppUser(
        uid: cred.user!.uid,
        email: cred.user!.email ?? googleUser.email,
        displayName: cred.user!.displayName ?? googleUser.displayName ?? 'User',
        userId: (cred.user!.email ?? googleUser.email).split('@').first,
        photoUrl: cred.user!.photoURL ?? googleUser.photoUrl,
        deviceDetails: deviceDetails,
        emailVerified: true,
        createdAt: now,
        trialStartedAt: now,
        subscriptionExpiresAt: AppConstants.trialEndsAt(now),
        lastExpiresAt: AppConstants.trialEndsAt(now),
        isTrialActive: true,
      );
      user = user.copyWith(deviceDetails: deviceDetails);
      if (user.isBlocked && !AppConstants.isAdminEmail(user.email)) {
        await _auth.signOut();
        await _googleSignIn.signOut();
        throw AuthFailure('This account has been blocked by admin');
      }
      await _firestore.collection(AppConstants.colUsers).doc(user.uid).set(
        {
          ...user.toMap(),
          'lastActiveAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
      // Stable Google account id — not written to Firestore; regenerable after Google login.
      await _syncMasterKey(
        user.uid,
        wrapSecret: 'google:${googleUser.id}',
      );
      _setCurrent(user);
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure('Google sign-in failed: $e');
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    _requireFirebase();
    _validateEmail(email);
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    _requireFirebase();
    await _auth.currentUser?.sendEmailVerification();
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (_) {}
    // Keep the on-device master key for the same account (password reset / re-login).
    // It is cleared only when a different uid signs in.
    _setCurrent(null);
  }

  /// After Firebase password reset: unlock vault with app PIN, then re-wrap
  /// with the new account password.
  Future<void> recoverVaultWithPin({
    required String uid,
    required String newPassword,
    required String pin,
  }) async {
    _requireFirebase();
    final encSvc = EncryptionService.instance;
    final doc =
        await _firestore.collection(AppConstants.colUsers).doc(uid).get();
    final data = doc.data() ?? <String, dynamic>{};
    final wrapped = data[AppConstants.fieldWrappedMasterKeyByPin] as String?;
    final salt = data[AppConstants.fieldMasterKeyPinWrapSalt] as String?;
    if (wrapped == null ||
        wrapped.isEmpty ||
        salt == null ||
        salt.isEmpty) {
      throw AuthFailure(
        'PIN vault recovery is not set up on this account yet. '
        'Start a fresh vault, or sign in on a device that still has the vault unlocked.',
      );
    }
    try {
      final local = encSvc.unwrapMasterKey(wrapped, _pinWrapSecret(pin), salt);
      await _storage.saveMasterKey(local);
      await _storage.write(AppConstants.keyLastVaultUid, uid);
      await _uploadWrappedMasterKey(uid, local, newPassword);
      await _uploadPinWrappedMasterKey(uid, local, pin);
    } on EncryptionException {
      throw AuthFailure('Incorrect app PIN, or vault recovery data is invalid.');
    }
  }

  /// Creates a new empty vault encryption key (old encrypted passwords become unreadable).
  Future<void> startFreshVault({
    required String uid,
    required String newPassword,
    String? pin,
  }) async {
    _requireFirebase();
    final encSvc = EncryptionService.instance;
    final local = encSvc.generateMasterKey();
    await _storage.saveMasterKey(local);
    await _storage.write(AppConstants.keyLastVaultUid, uid);
    await _uploadWrappedMasterKey(uid, local, newPassword);
    if (pin != null && pin.isNotEmpty) {
      await _uploadPinWrappedMasterKey(uid, local, pin);
    }
  }

  @override
  Future<void> updateProfile(AppUser user) async {
    _requireFirebase();
    await _firestore
        .collection(AppConstants.colUsers)
        .doc(user.uid)
        .set(user.toMap(), SetOptions(merge: true));
    _setCurrent(user);
  }

  @override
  Future<AppUser?> reloadCurrentUser() async {
    _requireFirebase();
    final uid = _auth.currentUser?.uid ?? _current?.uid;
    if (uid == null) return null;
    final loaded = await _loadUserDoc(uid);
    if (loaded != null) _setCurrent(loaded);
    return loaded;
  }

  @override
  Future<bool> verifyRecovery({
    String? email,
    String? primaryMobile,
    String? secondaryMobile,
    String? appPin,
  }) async {
    // Only the signed-in user's own doc is readable under Firestore rules
    // (no collection-wide email queries).
    AppUser? user = _current;
    if (user == null && _auth.currentUser != null) {
      user = await _loadUserDoc(_auth.currentUser!.uid);
    }
    if (user == null) return false;

    var matches = 0;
    if (email != null &&
        email.trim().isNotEmpty &&
        email.trim().toLowerCase() == user.email.toLowerCase()) {
      matches++;
    }
    if (primaryMobile != null &&
        primaryMobile.trim().isNotEmpty &&
        primaryMobile.trim() == (user.primaryMobile ?? '')) {
      matches++;
    }
    if (secondaryMobile != null &&
        secondaryMobile.trim().isNotEmpty &&
        secondaryMobile.trim() == (user.secondaryMobile ?? '')) {
      matches++;
    }
    if (appPin != null && appPin.isNotEmpty) {
      final salt = await _storage.read(AppConstants.keyAppPinSalt) ??
          await _storage.read(AppConstants.keyEncryptionSalt) ??
          '';
      final hash = await _storage.read(AppConstants.keyAppPinHash);
      if (hash != null &&
          salt.isNotEmpty &&
          EncryptionService.instance.verifyPin(appPin, salt, hash)) {
        matches++;
      }
    }
    // Need at least two factors (requirement 11)
    return matches >= 2;
  }

  Future<AppUser?> _loadUserDoc(String uid) async {
    final doc =
        await _firestore.collection(AppConstants.colUsers).doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return AppUser.fromMap(doc.data()!);
  }

  /// Ensures a local master key and uploads an *encrypted* copy to Firestore.
  ///
  /// [wrapSecret] is the account password (email login) or a stable Google id.
  /// Without it (cold bootstrap), only an existing on-device key is used.
  Future<void> _syncMasterKey(String uid, {String? wrapSecret}) async {
    _requireFirebase();
    final encSvc = EncryptionService.instance;

    await _prepareLocalKeyForAccount(uid);

    final doc =
        await _firestore.collection(AppConstants.colUsers).doc(uid).get();
    final data = doc.data() ?? <String, dynamic>{};

    final wrapped = data[AppConstants.fieldWrappedMasterKey] as String?;
    final wrapSalt = data[AppConstants.fieldMasterKeyWrapSalt] as String?;
    final legacyPlain = data[AppConstants.fieldMasterKeyBase64] as String?;

    var local = await _storage.getMasterKey();

    // Migrate legacy plaintext cloud key → wrapped, then scrub plaintext.
    if (legacyPlain != null && legacyPlain.isNotEmpty) {
      local ??= legacyPlain;
      await _storage.saveMasterKey(local);
      if (wrapSecret != null) {
        await _uploadWrappedMasterKey(uid, local, wrapSecret);
      }
    }

    if (local != null && local.isNotEmpty) {
      // Always re-wrap when we know the account secret so password resets
      // on this device update the cloud wrap to the new password.
      if (wrapSecret != null && wrapSecret.isNotEmpty) {
        await _uploadWrappedMasterKey(uid, local, wrapSecret);
      }
    } else if (wrapped != null &&
        wrapped.isNotEmpty &&
        wrapSalt != null &&
        wrapSalt.isNotEmpty) {
      if (wrapSecret == null || wrapSecret.isEmpty) {
        throw AuthFailure(
          'Please sign in again to unlock your vault on this device.',
        );
      }
      try {
        local = encSvc.unwrapMasterKey(wrapped, wrapSecret, wrapSalt);
        await _storage.saveMasterKey(local);
      } on EncryptionException {
        throw VaultKeyUnlockFailure(
          uid: uid,
          newPassword: wrapSecret,
          message:
              'Could not unlock vault encryption key. '
              'If you reset your account password, unlock with your app PIN '
              'or start a fresh vault.',
        );
      }
    } else {
      // Brand-new vault
      local = encSvc.generateMasterKey();
      await _storage.saveMasterKey(local);
      if (wrapSecret != null) {
        await _uploadWrappedMasterKey(uid, local, wrapSecret);
      }
    }

    await _storage.write(AppConstants.keyLastVaultUid, uid);
    await _scrubLegacyPlainMasterKey(uid);
    await _ensureEncryptionSalt();
  }

  /// Drops the on-device master key when a different account signs in.
  Future<void> _prepareLocalKeyForAccount(String uid) async {
    final lastUid = await _storage.read(AppConstants.keyLastVaultUid);
    if (lastUid != null && lastUid.isNotEmpty && lastUid != uid) {
      await _storage.delete(AppConstants.keyMasterKey);
    }
  }

  String _pinWrapSecret(String pin) => 'pin:$pin';

  Future<void> _uploadWrappedMasterKey(
    String uid,
    String masterKeyBase64,
    String wrapSecret,
  ) async {
    final encSvc = EncryptionService.instance;
    final salt = encSvc.generateSalt();
    final wrapped = encSvc.wrapMasterKey(masterKeyBase64, wrapSecret, salt);
    await _firestore.collection(AppConstants.colUsers).doc(uid).set(
      {
        AppConstants.fieldWrappedMasterKey: wrapped,
        AppConstants.fieldMasterKeyWrapSalt: salt,
        AppConstants.fieldMasterKeyBase64: FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _uploadPinWrappedMasterKey(
    String uid,
    String masterKeyBase64,
    String pin,
  ) async {
    final encSvc = EncryptionService.instance;
    final salt = encSvc.generateSalt();
    final wrapped =
        encSvc.wrapMasterKey(masterKeyBase64, _pinWrapSecret(pin), salt);
    await _firestore.collection(AppConstants.colUsers).doc(uid).set(
      {
        AppConstants.fieldWrappedMasterKeyByPin: wrapped,
        AppConstants.fieldMasterKeyPinWrapSalt: salt,
      },
      SetOptions(merge: true),
    );
  }

  /// Call when the user creates/updates the app PIN so password-reset recovery works.
  Future<void> syncPinVaultWrap(String pin) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final local = await _storage.getMasterKey();
    if (local == null || local.isEmpty) return;
    await _uploadPinWrappedMasterKey(uid, local, pin);
  }

  Future<void> _scrubLegacyPlainMasterKey(String uid) async {
    try {
      await _firestore.collection(AppConstants.colUsers).doc(uid).set(
        {AppConstants.fieldMasterKeyBase64: FieldValue.delete()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _ensureEncryptionSalt() async {
    final salt = await _storage.read(AppConstants.keyEncryptionSalt);
    if (salt == null) {
      await _storage.write(
        AppConstants.keyEncryptionSalt,
        EncryptionService.instance.generateSalt(),
      );
    }
  }

  void _setCurrent(AppUser? user) {
    _current = user;
    _controller.add(user);
  }

  void _validateEmail(String email) {
    final regex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$');
    if (!regex.hasMatch(email.trim())) {
      throw AuthFailure('Enter a valid email address');
    }
  }

  void _validatePassword(String password) {
    if (password.length < 8) {
      throw AuthFailure('Password must be at least 8 characters');
    }
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Email is already registered';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-not-found':
        return 'No account found for this email';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password';
      case 'weak-password':
        return 'Password is too weak';
      case 'network-request-failed':
        return 'Network error. Check your connection';
      default:
        return e.message ?? 'Authentication failed';
    }
  }

  void dispose() {
    _controller.close();
  }
}

/// Domain auth failure.
class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Firebase login succeeded but vault key could not be unwrapped (e.g. password reset).
class VaultKeyUnlockFailure extends AuthFailure {
  VaultKeyUnlockFailure({
    required this.uid,
    required this.newPassword,
    String? message,
  }) : super(
          message ??
              'Could not unlock vault encryption key. '
                  'If you reset your account password, unlock with your app PIN '
                  'or start a fresh vault.',
        );

  final String uid;
  final String newPassword;
}
