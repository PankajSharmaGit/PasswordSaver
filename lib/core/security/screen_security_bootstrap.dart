import 'biometric_service.dart';

/// Bootstraps screenshot / recording protection at app start.
class ScreenSecurityBootstrap {
  ScreenSecurityBootstrap._();

  /// Blocks screenshots and screen recording inside the app.
  static const bool protectionEnabled = true;

  static Future<void> enable() async {
    if (protectionEnabled) {
      await ScreenSecurityService.instance.enableProtection();
    } else {
      await ScreenSecurityService.instance.disableProtection();
    }
  }
}
