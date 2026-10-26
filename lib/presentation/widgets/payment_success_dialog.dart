import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'common_widgets.dart';

/// Congratulations dialog shown after Razorpay payment is verified on the server.
class PaymentSuccessDialog extends StatefulWidget {
  const PaymentSuccessDialog({
    super.key,
    required this.planLabel,
    required this.amountLabel,
    this.expiresLabel,
    this.paymentId,
    this.primaryLabel = 'Continue',
    required this.onPrimary,
  });

  final String planLabel;
  final String amountLabel;
  final String? expiresLabel;
  final String? paymentId;
  final String primaryLabel;
  final VoidCallback onPrimary;

  /// Shows the dialog and completes when the user taps Continue/OK.
  static Future<void> show(
    BuildContext context, {
    required String planLabel,
    required String amountLabel,
    String? expiresLabel,
    String? paymentId,
    String primaryLabel = 'Continue',
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Payment success',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (ctx, animation, secondaryAnimation) => PaymentSuccessDialog(
        planLabel: planLabel,
        amountLabel: amountLabel,
        expiresLabel: expiresLabel,
        paymentId: paymentId,
        primaryLabel: primaryLabel,
        onPrimary: () => Navigator.of(ctx).pop(),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<PaymentSuccessDialog> createState() => _PaymentSuccessDialogState();
}

class _PaymentSuccessDialogState extends State<PaymentSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _autoClose = Timer(const Duration(seconds: 12), _onPrimary);
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onPrimary() {
    if (!mounted) return;
    _autoClose?.cancel();
    widget.onPrimary();
  }

  @override
  Widget build(BuildContext context) {
    final cardBorder = AppColors.isDark
        ? Colors.white.withValues(alpha: 0.12)
        : AppColors.mist.withValues(alpha: 0.45);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cardBorder),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: AppColors.isDark
                    ? [const Color(0xFF121A2E), const Color(0xFF0B1020)]
                    : [Colors.white, AppColors.sand.withValues(alpha: 0.95)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.teal.withValues(alpha: 0.22),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.mint,
                          AppColors.teal,
                          AppColors.foam,
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 96,
                          width: 96,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              FadeTransition(
                                opacity: Tween<double>(begin: 0.35, end: 0)
                                    .animate(_pulse),
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.85, end: 1.25)
                                      .animate(_pulse),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.teal
                                          .withValues(alpha: 0.25),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [AppColors.mint, AppColors.teal],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.teal
                                          .withValues(alpha: 0.45),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 16, color: AppColors.amber),
                            const SizedBox(width: 6),
                            Icon(Icons.celebration_outlined,
                                size: 18, color: AppColors.teal),
                            const SizedBox(width: 6),
                            Icon(Icons.auto_awesome,
                                size: 16, color: AppColors.amber),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Congratulations!',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your plan is active — ${widget.planLabel}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.slate,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : AppColors.teal.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.mist.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total paid',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: AppColors.slate),
                                  ),
                                  Text(
                                    widget.amountLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: AppColors.teal,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ],
                              ),
                              if (widget.expiresLabel != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  widget.expiresLabel!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.slate),
                                ),
                              ],
                              if (widget.paymentId != null &&
                                  widget.paymentId!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Payment · ${widget.paymentId!.length > 18 ? '${widget.paymentId!.substring(0, 18)}…' : widget.paymentId}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.slate
                                            .withValues(alpha: 0.85),
                                        fontSize: 11,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        VaultButton(
                          label: widget.primaryLabel,
                          icon: Icons.arrow_forward_rounded,
                          onPressed: _onPrimary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
