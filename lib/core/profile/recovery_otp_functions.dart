import 'package:cloud_functions/cloud_functions.dart';

/// Cloud Functions for recovery mobile / email OTP verification.
class RecoveryOtpFunctions {
  RecoveryOtpFunctions({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  Future<RecoveryOtpSendResult> sendOtp({
    required String channel,
    required String target,
  }) async {
    try {
      final result = await _functions.httpsCallable('sendRecoveryOtp').call({
        'channel': channel,
        'target': target,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return RecoveryOtpSendResult(
        ok: data['ok'] == true,
        channel: data['channel']?.toString() ?? channel,
        target: data['target']?.toString() ?? target,
        expiresInSec: (data['expiresInSec'] as num?)?.toInt() ?? 600,
        debugOtp: data['debugOtp']?.toString(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw RecoveryOtpException(e.message ?? e.code);
    }
  }

  Future<void> verifyOtp({
    required String channel,
    required String target,
    required String otp,
  }) async {
    try {
      await _functions.httpsCallable('verifyRecoveryOtp').call({
        'channel': channel,
        'target': target,
        'otp': otp,
      });
    } on FirebaseFunctionsException catch (e) {
      throw RecoveryOtpException(e.message ?? e.code);
    }
  }
}

class RecoveryOtpSendResult {
  const RecoveryOtpSendResult({
    required this.ok,
    required this.channel,
    required this.target,
    required this.expiresInSec,
    this.debugOtp,
  });

  final bool ok;
  final String channel;
  final String target;
  final int expiresInSec;
  final String? debugOtp;
}

class RecoveryOtpException implements Exception {
  RecoveryOtpException(this.message);
  final String message;

  @override
  String toString() => message;
}
