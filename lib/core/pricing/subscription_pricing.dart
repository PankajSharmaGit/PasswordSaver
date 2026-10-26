import '../../domain/entities/entities.dart';

/// INR for India (+ GST) · USD (+50% on converted base) for other countries.
class SubscriptionPricing {
  SubscriptionPricing._();

  static const double defaultInrToUsdRate = 0.012;
  static const double defaultInternationalMultiplier = 1.5;

  static bool isIndiaUser(AppUser? user) {
    final code = user?.countryCode?.trim().toUpperCase();
    return code == null || code.isEmpty || code == 'IN';
  }

  static String formatInr(int amount) => '₹$amount';

  static String formatUsd(double amount) =>
      '\$${amount.toStringAsFixed(2)}';

  static int inrGrandTotal({
    required int taxableInr,
    required SubscriptionGstConfig gst,
  }) =>
      gst.inrGrandTotal(taxableInr);

  static String formatPlanTotal({
    required int priceInr,
    required double priceUsd,
    required AppUser? user,
    SubscriptionGstConfig? gst,
  }) {
    if (isIndiaUser(user)) {
      final config = gst ?? const SubscriptionGstConfig();
      return formatInr(inrGrandTotal(taxableInr: priceInr, gst: config));
    }
    return formatUsd(priceUsd);
  }

  static String gstHint({
    required int taxableInr,
    required SubscriptionGstConfig gst,
  }) {
    if (gst.gstPercent <= 0) return '';
    final tax = gst.gstOn(taxableInr).round();
    return '${formatInr(taxableInr)} + ${gst.gstPercent.toStringAsFixed(0)}% GST (${formatInr(tax)})';
  }

  static String perMonthLabel({
    required int totalInr,
    required double totalUsd,
    required int months,
    required AppUser? user,
    SubscriptionGstConfig? gst,
  }) {
    if (isIndiaUser(user)) {
      final config = gst ?? const SubscriptionGstConfig();
      final grand = inrGrandTotal(taxableInr: totalInr, gst: config);
      return '${formatInr((grand / months).round())} / month incl. GST';
    }
    return '${formatUsd(totalUsd / months)} / month';
  }

  static String regionHint(AppUser? user, {SubscriptionGstConfig? gst}) {
    if (isIndiaUser(user)) {
      final pct = gst?.gstPercent ?? 18;
      return 'India pricing (INR · +${pct.toStringAsFixed(0)}% GST)';
    }
    final country = user?.countryName ?? user?.countryCode ?? 'International';
    return '$country pricing (USD · +50% on base rate)';
  }

  static bool amountsMatch({
    required num paidAmount,
    required int catalogInr,
    required double catalogUsd,
    required bool paidInUsd,
    SubscriptionGstConfig? gst,
  }) {
    if (paidInUsd) {
      return (paidAmount - catalogUsd).abs() < 0.01;
    }
    final expected = gst != null
        ? inrGrandTotal(taxableInr: catalogInr, gst: gst)
        : catalogInr;
    return paidAmount.round() == expected;
  }
}
