import 'package:cloud_functions/cloud_functions.dart';

/// User profile actions verified on the server.
class UserCloudFunctions {
  UserCloudFunctions({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  /// Saves country once per account (backend validates code + name).
  Future<UserCountryResult> setUserCountry({
    required String countryCode,
    required String countryName,
  }) async {
    try {
      final result = await _functions.httpsCallable('setUserCountry').call({
        'countryCode': countryCode,
        'countryName': countryName,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return UserCountryResult(
        ok: data['ok'] == true,
        countryCode: data['countryCode']?.toString() ?? countryCode,
        countryName: data['countryName']?.toString() ?? countryName,
      );
    } on FirebaseFunctionsException catch (e) {
      throw UserCloudException(e.message ?? e.code);
    }
  }
}

class UserCountryResult {
  const UserCountryResult({
    required this.ok,
    required this.countryCode,
    required this.countryName,
  });

  final bool ok;
  final String countryCode;
  final String countryName;
}

class UserCloudException implements Exception {
  UserCloudException(this.message);
  final String message;

  @override
  String toString() => message;
}
