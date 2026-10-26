import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/pricing/subscription_tax.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import 'common_widgets.dart';

/// Pre-checkout tax invoice (Snapbilling-style) — GSTIN + bill breakdown.
class SubscriptionBillDialog extends StatefulWidget {
  const SubscriptionBillDialog({
    super.key,
    required this.planLine,
    required this.taxableInr,
    required this.gst,
    required this.buyerName,
    this.initialGstin,
  });

  final String planLine;
  final int taxableInr;
  final SubscriptionGstConfig gst;
  final String buyerName;
  final String? initialGstin;

  /// Returns buyer GSTIN on confirm, or `null` if cancelled.
  static Future<String?> show(
    BuildContext context, {
    required String planLine,
    required int taxableInr,
    required SubscriptionGstConfig gst,
    required String buyerName,
    String? initialGstin,
  }) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SubscriptionBillDialog(
        planLine: planLine,
        taxableInr: taxableInr,
        gst: gst,
        buyerName: buyerName,
        initialGstin: initialGstin,
      ),
    );
  }

  @override
  State<SubscriptionBillDialog> createState() => _SubscriptionBillDialogState();
}

class _SubscriptionBillDialogState extends State<SubscriptionBillDialog> {
  late final TextEditingController _gstinCtrl;

  @override
  void initState() {
    super.initState();
    _gstinCtrl = TextEditingController(text: widget.initialGstin ?? '');
  }

  @override
  void dispose() {
    _gstinCtrl.dispose();
    super.dispose();
  }

  void _onGstinChanged(String raw) {
    final cleaned =
        raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    final next = cleaned.length > 15 ? cleaned.substring(0, 15) : cleaned;
    if (next != _gstinCtrl.text) {
      _gstinCtrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
    setState(() {});
  }

  SubscriptionTaxBreakdown get _tax => SubscriptionTax.forCheckout(
        taxableInr: widget.taxableInr,
        gst: widget.gst,
        buyerGstin: _gstinCtrl.text,
      );

  String get _gstLabel {
    final pct = widget.gst.gstPercent;
    final pctText = pct % 1 == 0 ? pct.toInt().toString() : pct.toString();
    return 'GST ($pctText%)';
  }

  @override
  Widget build(BuildContext context) {
    final tax = _tax;
    final seller = widget.gst.platformLegalName.trim().isEmpty
        ? 'PasswordSaver'
        : widget.gst.platformLegalName.trim();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          seller,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          'Subscription invoice',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.slate,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (widget.gst.platformGstin.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'GSTIN: ${widget.gst.platformGstin.trim()}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppColors.slate,
                      ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Billed to',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate,
                      letterSpacing: 0.4,
                    ),
              ),
              Text(
                widget.buyerName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _gstinCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 15,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
                ],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  letterSpacing: 0.6,
                ),
                decoration: InputDecoration(
                  labelText: 'Your GSTIN (optional)',
                  hintText: '15-character GST number',
                  isDense: true,
                  counterText: '${_gstinCtrl.text.length}/15',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: _onGstinChanged,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.mist.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.mist.withValues(alpha: 0.6)),
                ),
                child: Column(
                  children: [
                    _line(widget.planLine, tax.taxableAmount),
                    const SizedBox(height: 8),
                    if (tax.isInterState) ...[
                      _line('IGST', tax.igst, muted: true),
                    ] else if (tax.totalGst > 0) ...[
                      _line('CGST', tax.cgst, muted: true),
                      const SizedBox(height: 4),
                      _line('SGST', tax.sgst, muted: true),
                    ] else
                      _line(_gstLabel, tax.totalGst, muted: true),
                    const Divider(height: 22),
                    _line('Total due', tax.grandTotal, bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              VaultButton(
                label:
                    'Confirm & pay · ₹${tax.grandTotal.toStringAsFixed(2)}',
                onPressed: () =>
                    Navigator.of(context).pop(_gstinCtrl.text.trim()),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String label, double amount, {bool bold = false, bool muted = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              fontSize: bold ? 15 : 13,
              color: muted ? AppColors.slate : null,
            ),
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontSize: bold ? 16 : 13,
            color: bold ? AppColors.teal : null,
          ),
        ),
      ],
    );
  }
}
