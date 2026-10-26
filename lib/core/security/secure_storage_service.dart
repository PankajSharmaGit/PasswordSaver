import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

/// Thin wrapper around flutter_secure_storage for sensitive local keys.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> clearAll() => _storage.deleteAll();

  Future<bool> hasAppPin() async {
    final hash = await read(AppConstants.keyAppPinHash);
    return hash != null && hash.isNotEmpty;
  }

  Future<String?> getMasterKey() => read(AppConstants.keyMasterKey);

  Future<void> saveMasterKey(String key) =>
      write(AppConstants.keyMasterKey, key);

  Future<bool> getReverifyOnView() async {
    final value = await read(AppConstants.keyReverifyOnView);
    // Default ON for security (requirement 8/10)
    return value != 'false';
  }

  Future<void> setReverifyOnView(bool enabled) =>
      write(AppConstants.keyReverifyOnView, enabled ? 'true' : 'false');

  /// Device system lock (PIN / pattern / fingerprint) on every app open.
  Future<bool> getDeviceLockOnOpen() async {
    final value = await read(AppConstants.keyDeviceLockOnOpen);
    return value == 'true';
  }

  Future<void> setDeviceLockOnOpen(bool enabled) =>
      write(AppConstants.keyDeviceLockOnOpen, enabled ? 'true' : 'false');

  /// Persisted appearance theme id (e.g. ocean, midnight).
  Future<String?> getAppThemeId() => read(AppConstants.keyAppThemeId);

  Future<void> setAppThemeId(String themeId) =>
      write(AppConstants.keyAppThemeId, themeId);
}
