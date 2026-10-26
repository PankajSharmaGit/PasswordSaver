import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

/// Captures device fingerprint details for login/signup (requirement 2, 11).
class DeviceInfoService {
  DeviceInfoService({DeviceInfoPlugin? plugin})
      : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;
  final _uuid = const Uuid();

  /// Collects a map of device identifiers and metadata.
  Future<Map<String, String>> collectDeviceDetails() async {
    try {
      final details = <String, String>{
        'collectedAt': DateTime.now().toUtc().toIso8601String(),
        'sessionId': _uuid.v4(),
      };

      if (Platform.isAndroid) {
        final info = await _plugin.androidInfo;
        details.addAll({
          'platform': 'android',
          'deviceId': info.id,
          'brand': info.brand,
          'model': info.model,
          'manufacturer': info.manufacturer,
          'androidVersion': info.version.release,
          'sdkInt': '${info.version.sdkInt}',
          'isPhysicalDevice': '${info.isPhysicalDevice}',
        });
      } else if (Platform.isIOS) {
        final info = await _plugin.iosInfo;
        details.addAll({
          'platform': 'ios',
          'deviceId': info.identifierForVendor ?? 'unknown',
          'name': info.name,
          'model': info.model,
          'systemVersion': info.systemVersion,
          'isPhysicalDevice': '${info.isPhysicalDevice}',
        });
      } else if (Platform.isWindows) {
        final info = await _plugin.windowsInfo;
        details.addAll({
          'platform': 'windows',
          'deviceId': info.deviceId,
          'computerName': info.computerName,
          'productName': info.productName,
        });
      } else {
        details['platform'] = Platform.operatingSystem;
        details['deviceId'] = _uuid.v4();
      }

      return details;
    } catch (e) {
      return {
        'platform': 'unknown',
        'deviceId': _uuid.v4(),
        'error': e.toString(),
      };
    }
  }

  /// Short readable label for UI.
  Future<String> deviceLabel() async {
    final details = await collectDeviceDetails();
    final brand = details['brand'] ?? details['name'] ?? details['platform'];
    final model = details['model'] ?? details['computerName'] ?? '';
    return '$brand $model'.trim();
  }
}
