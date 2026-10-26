import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../constants/app_constants.dart';

/// Result of a successful Razorpay checkout.
class RazorpayPaymentSuccess {
  const RazorpayPaymentSuccess({
    required this.paymentId,
    this.orderId,
    this.signature,
  });

  final String paymentId;
  final String? orderId;
  final String? signature;
}

/// Thin wrapper around [Razorpay] checkout (UPI / card / netbanking via SDK).
class RazorpayPaymentService {
  RazorpayPaymentService() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  late final Razorpay _razorpay;
  Completer<RazorpayPaymentSuccess?>? _pending;

  /// Opens Razorpay checkout. Prefer [orderId] from Cloud Function.
  /// [amountMinor] is paise (INR) or cents (USD).
  Future<RazorpayPaymentSuccess?> checkout({
    required int amountMinor,
    required String currency,
    required String description,
    required String keyId,
    String? orderId,
    String? email,
    String? contact,
    String? name,
  }) async {
    final key = keyId.trim();
    if (key.isEmpty) {
      throw StateError(
        'Payment is not configured. Missing Razorpay Key ID from server.',
      );
    }
    if (_pending != null && !_pending!.isCompleted) {
      throw StateError('Another payment is already in progress');
    }

    _pending = Completer<RazorpayPaymentSuccess?>();
    final options = <String, dynamic>{
      'key': key,
      'amount': amountMinor,
      'currency': currency.toUpperCase(),
      'name': AppConstants.appName,
      'description': description,
      'image': AppConstants.razorpayCheckoutLogoUrl,
      'retry': {'enabled': true, 'max_count': 2},
      if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
      'prefill': {
        if (email != null && email.isNotEmpty) 'email': email,
        if (contact != null && contact.isNotEmpty) 'contact': contact,
        if (name != null && name.isNotEmpty) 'name': name,
      },
      'theme': {'color': '#0D9488'},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      _pending?.completeError(e);
      _pending = null;
      rethrow;
    }

    return _pending!.future;
  }

  void _onSuccess(PaymentSuccessResponse response) {
    final c = _pending;
    _pending = null;
    if (c == null || c.isCompleted) return;
    final id = response.paymentId;
    if (id == null || id.isEmpty) {
      c.complete(null);
      return;
    }
    c.complete(
      RazorpayPaymentSuccess(
        paymentId: id,
        orderId: response.orderId,
        signature: response.signature,
      ),
    );
  }

  void _onError(PaymentFailureResponse response) {
    final c = _pending;
    _pending = null;
    if (c == null || c.isCompleted) return;
    c.complete(null);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // User selected an external wallet — wait for success/error events.
  }

  void dispose() {
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.complete(null);
    }
    _pending = null;
    _razorpay.clear();
  }
}
