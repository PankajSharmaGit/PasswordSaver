import '../entities/entities.dart';

/// Auth contract — Firebase or local demo implementation.
abstract class AuthRepository {
  Stream<AppUser?> get authStateChanges;

  AppUser? get currentUser;

  Future<AppUser> signUp({
    required String displayName,
    required String userId,
    required String email,
    required String password,
    required String primaryMobile,
    String? secondaryMobile,
    required Map<String, String> deviceDetails,
  });

  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
    required Map<String, String> deviceDetails,
  });

  Future<AppUser> signInWithGoogle({
    required Map<String, String> deviceDetails,
  });

  Future<void> sendPasswordResetEmail(String email);

  Future<void> sendEmailVerification();

  Future<void> signOut();

  Future<void> updateProfile(AppUser user);

  /// Reloads the signed-in user document from Firestore.
  Future<AppUser?> reloadCurrentUser();

  /// Two-way recovery when email/device is lost (requirement 11).
  Future<bool> verifyRecovery({
    String? email,
    String? primaryMobile,
    String? secondaryMobile,
    String? appPin,
  });
}

/// Credential vault contract.
abstract class CredentialRepository {
  Stream<List<CredentialEntry>> watchCredentials(String userId);

  Future<List<CredentialEntry>> getCredentials(String userId);

  Future<CredentialEntry> addCredential(CredentialEntry entry);

  Future<CredentialEntry> updateCredential(CredentialEntry entry);

  /// Deletes local + Firestore credential. When attachment path(s) are set,
  /// also removes Firebase Storage / local attachments (queued if offline).
  Future<void> deleteCredential(
    String userId,
    String credentialId, {
    String? attachmentPath,
    List<String>? attachmentPaths,
  });
}

/// App PIN management contract (requirements 9, 10).
abstract class PinRepository {
  Future<bool> hasPin();

  Future<void> createPin(String pin);

  Future<bool> verifyPin(String pin);

  /// Update PIN only when old PIN is correct.
  Future<bool> updatePin({required String oldPin, required String newPin});

  /// Reset PIN after multi-factor recovery succeeds.
  Future<void> resetPin(String newPin);
}

/// Subscription contract (requirements 14, 15).
abstract class SubscriptionRepository {
  Future<void> activatePlan({
    required String userId,
    required int months,
    required int priceInr,
    DateTime? expiresAt,
    String? razorpayPaymentId,
    String? razorpayOrderId,
    String? razorpaySignature,
  });

  Future<DateTime?> getExpiry(String userId);

  /// Currently subscribed paid plan months, if any.
  Future<int?> getPlanMonths(String userId);
}
