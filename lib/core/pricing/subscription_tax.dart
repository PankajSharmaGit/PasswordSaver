import '../../domain/entities/entities.dart';

/// GST breakdown for India subscription checkout (matches Cloud Functions).
class SubscriptionTaxBreakdown {
  const SubscriptionTaxBreakdown({
    required this.taxableAmount,
    required this.gstPercent,
    required this.supplyType,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.totalGst,
    required this.grandTotal,
  });

  final double taxableAmount;
  final double gstPercent;
  final String supplyType;
  final double cgst;
  final double sgst;
  final double igst;
  final double totalGst;
  final double grandTotal;

  bool get isInterState => supplyType == 'INTER';
}

class SubscriptionTax {
  SubscriptionTax._();

  static String stateCodeFromGstin(String? gstin) {
    final g = (gstin ?? '').trim().toUpperCase();
    if (g.length < 2) return '';
    return g.substring(0, 2);
  }

  static String sellerStateCode(SubscriptionGstConfig gst) {
    final code = gst.platformStateCode.trim();
    if (code.length >= 2) return code.substring(0, 2).toUpperCase();
    return stateCodeFromGstin(gst.platformGstin);
  }

  static double _round2(double v) =>
      (v * 100).roundToDouble() / 100;

  static SubscriptionTaxBreakdown compute({
    required double taxableAmount,
    required double gstPercent,
    required String buyerStateCode,
    required String sellerStateCode,
  }) {
    final taxable = _round2(taxableAmount < 0 ? 0 : taxableAmount);
    final rate = gstPercent < 0 ? 0.0 : gstPercent.toDouble();
    final totalGst = _round2((taxable * rate) / 100);
    final buyer = buyerStateCode.trim();
    final seller = sellerStateCode.trim();
    final known = buyer.length == 2 && seller.length == 2;
    final inter = known && buyer != seller;

    if (inter) {
      return SubscriptionTaxBreakdown(
        taxableAmount: taxable,
        gstPercent: rate,
        supplyType: 'INTER',
        cgst: 0,
        sgst: 0,
        igst: totalGst,
        totalGst: totalGst,
        grandTotal: _round2(taxable + totalGst),
      );
    }

    final half = _round2(totalGst / 2);
    final cgst = half;
    final sgst = _round2(totalGst - half);
    return SubscriptionTaxBreakdown(
      taxableAmount: taxable,
      gstPercent: rate,
      supplyType: 'INTRA',
      cgst: cgst,
      sgst: sgst,
      igst: 0,
      totalGst: _round2(cgst + sgst),
      grandTotal: _round2(taxable + cgst + sgst),
    );
  }

  static SubscriptionTaxBreakdown forCheckout({
    required int taxableInr,
    required SubscriptionGstConfig gst,
    String? buyerGstin,
  }) {
    return compute(
      taxableAmount: taxableInr.toDouble(),
      gstPercent: gst.gstPercent,
      buyerStateCode: stateCodeFromGstin(buyerGstin),
      sellerStateCode: sellerStateCode(gst),
    );
  }
}
