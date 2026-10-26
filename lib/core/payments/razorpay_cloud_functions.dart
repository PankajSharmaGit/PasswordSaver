import 'package:cloud_functions/cloud_functions.dart';

/// Calls Firebase Cloud Functions for Razorpay order + signature verify.
class RazorpayCloudFunctions {
  RazorpayCloudFunctions({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  /// Creates a Razorpay order on the server (secret never leaves Cloud Functions).
  Future<RazorpayOrderResult> createOrder({
    required int months,
    String planType = 'subscription',
    bool includeFilePlan = false,
    String? buyerGstin,
  }) async {
    try {
      final result = await _functions.httpsCallable('createRazorpayOrder').call({
        'months': months,
        'planType': planType,
        'includeFilePlan': includeFilePlan,
        if (buyerGstin != null && buyerGstin.trim().isNotEmpty)
          'buyerGstin': buyerGstin.trim().toUpperCase(),
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return RazorpayOrderResult(
        orderId: data['orderId'] as String,
        amountMinor: (data['amountMinor'] as num?)?.toInt() ??
            (data['amountPaise'] as num?)?.toInt() ??
            0,
        currency: data['currency'] as String? ?? 'INR',
        keyId: data['keyId'] as String?,
        months: data['months'] as int,
        priceInr: (data['priceInr'] as num?)?.toInt() ?? 0,
        priceUsd: (data['priceUsd'] as num?)?.toDouble(),
        grandTotalInr: (data['grandTotalInr'] as num?)?.toInt(),
        gstPercent: (data['gstPercent'] as num?)?.toDouble(),
        totalGst: (data['totalGst'] as num?)?.toDouble(),
        cgst: (data['cgst'] as num?)?.toDouble(),
        sgst: (data['sgst'] as num?)?.toDouble(),
        igst: (data['igst'] as num?)?.toDouble(),
        supplyType: data['supplyType']?.toString(),
        planType: data['planType']?.toString() ?? planType,
        maxAttachmentFiles: (data['maxAttachmentFiles'] as num?)?.toInt(),
        includeFilePlan: data['includeFilePlan'] == true,
        basePriceInr: (data['basePriceInr'] as num?)?.toInt(),
        filePlanPriceInr: (data['filePlanPriceInr'] as num?)?.toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw RazorpayCloudException(e.message ?? e.code);
    }
  }

  /// Verifies payment signature and activates subscription / file plan.
  Future<RazorpayVerifyResult> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    required int months,
    String planType = 'subscription',
  }) async {
    try {
      final result =
          await _functions.httpsCallable('verifyRazorpayPayment').call({
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
        'months': months,
        'planType': planType,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return RazorpayVerifyResult(
        ok: data['ok'] == true,
        expiresAt: data['expiresAt']?.toString(),
        months: data['months'] as int? ?? months,
        priceInr: data['priceInr'] as int?,
        paymentId: data['paymentId']?.toString(),
        alreadyProcessed: data['alreadyProcessed'] == true,
        planType: data['planType']?.toString() ?? planType,
        maxAttachmentFiles: (data['maxAttachmentFiles'] as num?)?.toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw RazorpayCloudException(e.message ?? e.code);
    }
  }
}

class RazorpayOrderResult {
  const RazorpayOrderResult({
    required this.orderId,
    required this.amountMinor,
    required this.currency,
    required this.months,
    required this.priceInr,
    this.priceUsd,
    this.grandTotalInr,
    this.gstPercent,
    this.totalGst,
    this.cgst,
    this.sgst,
    this.igst,
    this.supplyType,
    this.keyId,
    this.planType = 'subscription',
    this.maxAttachmentFiles,
    this.includeFilePlan = false,
    this.basePriceInr,
    this.filePlanPriceInr,
  });

  final String orderId;
  final int amountMinor;
  final String currency;
  final String? keyId;
  final int months;
  final int priceInr;
  final double? priceUsd;
  final int? grandTotalInr;
  final double? gstPercent;
  final double? totalGst;
  final double? cgst;
  final double? sgst;
  final double? igst;
  final String? supplyType;
  final String planType;
  final int? maxAttachmentFiles;
  final bool includeFilePlan;
  final int? basePriceInr;
  final int? filePlanPriceInr;

  bool get isUsd => currency.toUpperCase() == 'USD';
}

class RazorpayVerifyResult {
  const RazorpayVerifyResult({
    required this.ok,
    required this.months,
    this.expiresAt,
    this.priceInr,
    this.paymentId,
    this.alreadyProcessed = false,
    this.planType = 'subscription',
    this.maxAttachmentFiles,
  });

  final bool ok;
  final String? expiresAt;
  final int months;
  final int? priceInr;
  final String? paymentId;
  final bool alreadyProcessed;
  final String planType;
  final int? maxAttachmentFiles;
}

class RazorpayCloudException implements Exception {
  RazorpayCloudException(this.message);
  final String message;

  @override
  String toString() => message;
}
