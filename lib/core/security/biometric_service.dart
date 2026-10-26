import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:screen_protector/screen_protector.dart';

/// Device biometric / PIN / pattern authentication (requirement 8).
class BiometricService {
  BiometricService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  /// Returns true if device supports biometrics or device credentials.
  Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      return canCheck || supported;
    } catch (_) {
      return false;
    }
  }

  /// Prompts fingerprint / face / device PIN / pattern.
  Future<bool> authenticate({
    String reason = 'Verify your identity to continue',
  }) async {
    try {
      final available = await canAuthenticate();
      if (!available) return false;

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// Blocks screenshots and screen recording where supported (requirement 19).
class ScreenSecurityService {
  ScreenSecurityService._();
  static final ScreenSecurityService instance = ScreenSecurityService._();

  /// Enables FLAG_SECURE-style protection via screen_protector plugin.
  Future<void> enableProtection() async {
    try {
      await ScreenProtector.protectDataLeakageOn();
      await ScreenProtector.preventScreenshotOn();
    } catch (_) {
      // Best-effort; Android FLAG_SECURE in MainActivity is the primary guard.
    }
  }

  Future<void> disableProtection() async {
    try {
      await ScreenProtector.protectDataLeakageOff();
      await ScreenProtector.preventScreenshotOff();
    } catch (_) {}
  }
}
