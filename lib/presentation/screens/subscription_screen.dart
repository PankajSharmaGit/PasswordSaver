import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/admin/admin_cloud_functions.dart';
import '../../core/navigation/vault_routes.dart';
import '../../core/payments/razorpay_cloud_functions.dart';
import '../../core/payments/razorpay_payment_service.dart';
import '../../core/pricing/subscription_pricing.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/payment_success_dialog.dart';
import '../widgets/subscription_bill_dialog.dart';
import 'invite_screen.dart';

/// Subscription plans — Razorpay checkout for subscribe / upgrade.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    this.requiredUpgrade = false,
    this.renewFilePlan = false,
  });

  /// When true, trial/plan expired — user must subscribe (no back navigation).
  final bool requiredUpgrade;

  /// When true, starts checkout for the file plan matching the active base plan.
  final bool renewFilePlan;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _razorpay = RazorpayPaymentService();
  static final _dateFmt = DateFormat('dd MMM yyyy');
  bool _startedFileRenewal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<VaultAppState>();
      await state.refreshSubscriptionCatalog();
      if (!mounted || !widget.renewFilePlan || _startedFileRenewal) return;
      final months = state.user?.subscriptionPlanMonths;
      final filePlan = state.subscriptionCatalog.fileUpgradeForMonths(months);
      if (filePlan == null || state.user?.hasPaidPlan != true) return;
      if (state.user?.hasActiveFilePlan == true) return;
      _startedFileRenewal = true;
      await _maybeShowBillThenPay(
        months: filePlan.months,
        priceInr: filePlan.priceInr,
        isUpgrade: false,
        planType: 'file',
      );
    });
  }

  @override
  void dispose() {
    _razorpay.dispose();
    super.dispose();
  }

  String _expiredMessage(VaultAppState state) {
    final user = state.user;
    final end = user?.effectiveExpiresAt;
    final endLabel = end == null ? '' : _dateFmt.format(end.toLocal());
    if (user?.isTrialActive == true) {
      return endLabel.isEmpty
          ? 'Your plan has expired. Choose a plan to continue using PasswordSaver.'
          : 'Your free trial expired on $endLabel. Choose a plan to continue using PasswordSaver.';
    }
    if (user?.subscriptionPlanMonths != null) {
      final m = user!.subscriptionPlanMonths;
      return endLabel.isEmpty
          ? 'Your $m-month plan has expired. Renew or upgrade to restore access.'
          : 'Your $m-month plan expired on $endLabel. Renew or upgrade to restore access.';
    }
    return endLabel.isEmpty
        ? 'Your plan has expired. Upgrade now to continue using PasswordSaver.'
        : 'Your plan expired on $endLabel. Upgrade now to continue using PasswordSaver.';
  }

  String _requiredAccessTitle(VaultAppState state) {
    final user = state.user;
    if (user?.isExpiredPaidPlan == true) return 'Renew subscription';
    return 'Upgrade required';
  }

  String _requiredAccessSubtitle(VaultAppState state) {
    final user = state.user;
    if (user?.isExpiredPaidPlan == true) {
      final months = user!.lastPaidPlanMonths;
      return 'Your $months-month plan has ended. Renew the same plan or choose a higher one — vault access returns after payment.';
    }
    return 'Choose a plan and pay securely with UPI, card, or netbanking.';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultAppState>();
    final user = state.user;
    final gst = state.subscriptionCatalog.gst;
    final activePlan =
        user?.hasPaidPlan == true ? user!.subscriptionPlanMonths : null;
    final referencePlan = activePlan ?? user?.lastPaidPlanMonths;
    final trialActive = user?.isTrialActive == true && user!.hasActiveAccess;
    final requiredUpgrade = widget.requiredUpgrade;
    final expiredPaid = user?.isExpiredPaidPlan == true;

    return PopScope(
      canPop: !requiredUpgrade,
      child: Scaffold(
        body: VaultBackground(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (!requiredUpgrade)
                  IconButton(
                    alignment: Alignment.centerLeft,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Text(
                  requiredUpgrade ? _requiredAccessTitle(state) : 'Subscription',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 8),
                if (requiredUpgrade) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.coral.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.coral.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      _expiredMessage(state),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _requiredAccessSubtitle(state),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ] else
                  Text(
                    user?.isLifetimeFree == true
                        ? 'You have lifetime free access — no expiry. Paid plans are optional if you want more files.'
                        : activePlan != null
                            ? 'You are on the $activePlan-month plan. Upgrade anytime to a higher plan.'
                            : expiredPaid
                                ? 'Your plan expired — renew or upgrade below to restore vault access.'
                            : trialActive
                                ? 'Free for ${AppConstants.freeTrialDays} days — choose a paid plan when ready.'
                                : 'Choose a plan to keep protecting your passwords.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                if (user?.effectiveTrialStartedAt != null ||
                    user?.effectiveExpiresAt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    [
                      if (user?.effectiveTrialStartedAt != null)
                        'Trial started: ${_dateFmt.format(user!.effectiveTrialStartedAt!.toLocal())}',
                      if (user?.effectiveExpiresAt != null)
                        '${user!.hasActiveAccess ? 'Expires' : 'Last expired'}: ${_dateFmt.format(user.effectiveExpiresAt!.toLocal())}',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.foam,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.teal.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.attach_file_rounded, color: AppColors.teal),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'File storage: ${state.attachmentUsageLabel}'
                          '${state.canAddAttachment ? '' : ' · limit reached — upgrade below'}',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (AppConstants.inviteFriendsEnabled) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const InviteScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.foam,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.teal.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.card_giftcard, color: AppColors.teal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Invite friends · 50 pts / share · 200 pts = 1 month',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: AppColors.teal),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Subscription plans',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Base access + free file storage with each plan. '
                  'Upgrade replaces your current base period (remaining days are not added).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  SubscriptionPricing.regionHint(user, gst: gst),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.teal,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 16),
                ...state.subscriptionCatalog.plans.map((plan) {
                  final months = plan.months;
                  final priceInr = plan.priceInr;
                  final priceUsd = plan.usdPrice(state.subscriptionCatalog);
                  final perMonth = SubscriptionPricing.perMonthLabel(
                    totalInr: priceInr,
                    totalUsd: priceUsd,
                    months: months,
                    user: user,
                    gst: gst,
                  );
                  final isCurrent = activePlan == months;
                  final isRenew = expiredPaid && referencePlan == months;
                  final isLower =
                      referencePlan != null && months < referencePlan;
                  final isUpgrade =
                      referencePlan != null && months > referencePlan;
                  final canBuy = !isCurrent && !isLower;
                  final highlightPlan = isCurrent || isRenew || months == 12;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: (!canBuy || state.isLoading)
                          ? null
                          : () => _onSelectBasePlan(
                                plan: plan,
                                isUpgrade: isUpgrade,
                                isRenew: isRenew,
                              ),
                      borderRadius: BorderRadius.circular(18),
                      child: Opacity(
                        opacity: isLower ? 0.55 : 1,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: highlightPlan
                                  ? AppColors.teal
                                  : AppColors.mist.withValues(alpha: 0.5),
                              width: highlightPlan ? 1.8 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$months months · ${plan.maxAttachmentFiles} files free',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    Text(
                                      perMonth,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    if (isRenew)
                                      Text(
                                        'Your previous plan — tap to renew',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: AppColors.teal,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    if (months == 12 && !isCurrent && !isRenew)
                                      Text(
                                        'Best value',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: AppColors.amber,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    if (isLower)
                                      Text(
                                        'Lower than current plan',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    SubscriptionPricing.formatPlanTotal(
                                      priceInr: priceInr,
                                      priceUsd: priceUsd,
                                      user: user,
                                      gst: gst,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(color: AppColors.teal),
                                  ),
                                  const SizedBox(height: 6),
                                  _PlanBadge(
                                    isCurrent: isCurrent,
                                    isRenew: isRenew,
                                    isUpgrade: isUpgrade,
                                    canBuy: canBuy && !isUpgrade && !isRenew,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Text(
                  'Free trial · ${state.subscriptionCatalog.trialMaxAttachmentFiles} files free',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                Text(
                  'Upgrade file plans',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Optional add-on matching your current base plan. '
                  'If you upgrade base later, remaining file-plan time stays until it expires. '
                  'After that, files within the new free quota stay open; extras need a new file plan.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (user?.hasActiveFilePlan == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${state.attachmentFileLimit} files '
                    '(${state.baseAttachmentFileLimit} free + '
                    '${state.upgradeAttachmentFileLimit} upgrade)'
                    '${user!.filePlanExpiresAt != null ? ' · until ${_dateFmt.format(user.filePlanExpiresAt!.toLocal())}' : ''}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.teal,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                if (referencePlan == null)
                  Text(
                    'Select a base plan first — you can include a file plan at checkout, '
                    'or add it here after subscribe.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else if (expiredPaid)
                  Text(
                    'Renew your $referencePlan-month base plan above first. '
                    'You can add a file plan again after your subscription is active.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                  )
                else
                  ...state.subscriptionCatalog.fileUpgradePlans
                      .where((p) => p.months == referencePlan)
                      .map((plan) {
                    final isCurrentFile = user?.hasActiveFilePlan == true &&
                        user!.filePlanMonths == plan.months;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: (state.isLoading || isCurrentFile)
                            ? null
                            : () => _maybeShowBillThenPay(
                                  months: plan.months,
                                  priceInr: plan.priceInr,
                                  isUpgrade: false,
                                  planType: 'file',
                                ),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isCurrentFile
                                  ? AppColors.teal
                                  : AppColors.mist.withValues(alpha: 0.5),
                              width: isCurrentFile ? 1.8 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Add to your $referencePlan-month plan',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    Text(
                                      '+${plan.maxAttachmentFiles} files · expires with base plan',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: AppColors.teal,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    SubscriptionPricing.formatPlanTotal(
                                      priceInr: plan.priceInr,
                                      priceUsd: plan.usdPrice(
                                        state.subscriptionCatalog,
                                      ),
                                      user: user,
                                      gst: gst,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(color: AppColors.teal),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isCurrentFile ? 'Included' : 'Add files',
                                    style: TextStyle(
                                      color: AppColors.slate,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                Text(
                  'Secure checkout · payment is verified before your plan activates.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onSelectBasePlan({
    required SubscriptionPlan plan,
    required bool isUpgrade,
    bool isRenew = false,
  }) async {
    final state = context.read<VaultAppState>();
    final user = state.user;
    final catalog = state.subscriptionCatalog;
    final filePlan = catalog.fileUpgradeForMonths(plan.months);
    var includeFile = false;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sand,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final filePriceInr = filePlan?.priceInr ?? 0;
            final filePriceUsd = filePlan?.usdPrice(catalog) ?? 0;
            final fileCount = filePlan?.maxAttachmentFiles ?? 0;
            final planUsd = plan.usdPrice(catalog);
            final totalInr =
                plan.priceInr + (includeFile ? filePriceInr : 0);
            final totalUsd =
                planUsd + (includeFile ? filePriceUsd : 0);
            final baseLabel = SubscriptionPricing.formatPlanTotal(
              priceInr: plan.priceInr,
              priceUsd: planUsd,
              user: user,
              gst: catalog.gst,
            );
            final totalLabel = SubscriptionPricing.formatPlanTotal(
              priceInr: totalInr,
              priceUsd: totalUsd,
              user: user,
              gst: catalog.gst,
            );
            final fileAddLabel = SubscriptionPricing.formatPlanTotal(
              priceInr: filePriceInr,
              priceUsd: filePriceUsd,
              user: user,
              gst: catalog.gst,
            );
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isRenew
                          ? 'Renew · ${plan.months} months'
                          : isUpgrade
                              ? 'Upgrade to ${plan.months} months'
                              : 'Subscribe · ${plan.months} months',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isRenew
                          ? 'Starts today for ${plan.months} months. '
                              '$baseLabel · ${plan.maxAttachmentFiles} files free'
                          : isUpgrade
                              ? 'New base starts today for ${plan.months} months '
                                  '(remaining days on current plan are not carried over). '
                                  '$baseLabel · ${plan.maxAttachmentFiles} files free'
                              : 'Base: $baseLabel · ${plan.maxAttachmentFiles} files free',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                    if (isUpgrade &&
                        state.user?.hasActiveFilePlan == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Your current file plan stays active until '
                        '${state.user!.filePlanExpiresAt != null ? _dateFmt.format(state.user!.filePlanExpiresAt!.toLocal()) : 'it expires'}.',
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: AppColors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (filePlan != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.mist.withValues(alpha: 0.5),
                          ),
                        ),
                        child: CheckboxListTile(
                          value: includeFile,
                          activeColor: AppColors.teal,
                          onChanged: (v) =>
                              setModal(() => includeFile = v == true),
                          title: Text(
                            'Include file plan (+$fileCount files)',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            isUpgrade
                                ? '+$fileAddLabel · replaces file plan until new base ends'
                                : '+$fileAddLabel · expires with base plan',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Total: $totalLabel',
                      style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                            color: AppColors.teal,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 16),
                    VaultButton(
                      label: 'Pay $totalLabel',
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _maybeShowBillThenPay(
      months: plan.months,
      priceInr: plan.priceInr,
      isUpgrade: isUpgrade,
      isRenew: isRenew,
      planType: 'subscription',
      includeFilePlan: includeFile,
    );
  }

  /// India: Snapbilling-style invoice with optional GSTIN before Razorpay.
  Future<void> _maybeShowBillThenPay({
    required int months,
    required int priceInr,
    required bool isUpgrade,
    bool isRenew = false,
    String planType = 'subscription',
    bool includeFilePlan = false,
  }) async {
    final state = context.read<VaultAppState>();
    final user = state.user;
    final catalog = state.subscriptionCatalog;

    var taxableInr = priceInr;
    if (planType == 'subscription' && includeFilePlan) {
      final file = catalog.fileUpgradeForMonths(months);
      taxableInr = priceInr + (file?.priceInr ?? 0);
    }

    String? buyerGstin;
    if (SubscriptionPricing.isIndiaUser(user)) {
      final planLine = AppConstants.razorpayCheckoutDescription(
        months: months,
        isUpgrade: isUpgrade,
        isRenew: isRenew,
        isFilePlan: planType == 'file',
        includeFilePlan: includeFilePlan,
      );
      final gstin = await SubscriptionBillDialog.show(
        context,
        planLine: planLine,
        taxableInr: taxableInr,
        gst: catalog.gst,
        buyerName: user?.displayName ?? user?.email ?? 'Customer',
        initialGstin: user?.buyerGstin,
      );
      if (!mounted) return;
      if (gstin == null) return;
      buyerGstin = gstin.isEmpty ? null : gstin;
    }

    await _payWithRazorpay(
      months: months,
      priceInr: priceInr,
      isUpgrade: isUpgrade,
      isRenew: isRenew,
      planType: planType,
      includeFilePlan: includeFilePlan,
      buyerGstin: buyerGstin,
    );
  }

  Future<void> _showPaymentWelcomeDialog({
    required VaultAppState state,
    required RazorpayOrderResult order,
    required int months,
    required String planType,
    required bool includeFilePlan,
    required bool isUpgrade,
    String? paymentId,
    String primaryLabel = 'Continue',
  }) async {
    final user = state.user;
    final isFilePlan = planType == 'file';

    String planLabel;
    if (isFilePlan) {
      final files = order.maxAttachmentFiles ?? '';
      planLabel = '$months-month file add-on (+$files files)';
    } else if (includeFilePlan) {
      planLabel = '$months-month plan + file plan';
    } else if (isUpgrade) {
      planLabel = '$months-month upgrade';
    } else {
      planLabel = '$months-month plan';
    }

    final amountLabel = order.isUsd
        ? SubscriptionPricing.formatUsd(order.priceUsd ?? 0)
        : SubscriptionPricing.formatInr(
            order.grandTotalInr ??
                SubscriptionPricing.inrGrandTotal(
                  taxableInr: order.priceInr,
                  gst: state.subscriptionCatalog.gst,
                ),
          );

    String? expiresLabel;
    if (isFilePlan) {
      final fileExpiry = user?.filePlanExpiresAt;
      if (fileExpiry != null) {
        expiresLabel =
            'File plan active until ${_dateFmt.format(fileExpiry.toLocal())}';
      }
    } else {
      final expiry = user?.effectiveExpiresAt;
      if (expiry != null) {
        expiresLabel =
            'Valid until ${_dateFmt.format(expiry.toLocal())}';
      }
    }

    await PaymentSuccessDialog.show(
      context,
      planLabel: planLabel,
      amountLabel: amountLabel,
      expiresLabel: expiresLabel,
      paymentId: paymentId,
      primaryLabel: primaryLabel,
    );
  }

  Future<void> _payWithRazorpay({
    required int months,
    required int priceInr,
    required bool isUpgrade,
    bool isRenew = false,
    String planType = 'subscription',
    bool includeFilePlan = false,
    String? buyerGstin,
  }) async {
    final state = context.read<VaultAppState>();
    final user = state.user;
    if (user == null) return;
    final isFilePlan = planType == 'file';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    try {
      final order = await state.createRazorpayOrder(
        months,
        planType: planType,
        includeFilePlan: includeFilePlan,
        buyerGstin: buyerGstin,
      );

      final keyId = order.keyId?.trim() ?? '';
      if (keyId.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment is not configured. Set PasswordSaver Razorpay keys in Firebase.',
            ),
          ),
        );
        return;
      }

      final payment = await _razorpay.checkout(
        amountMinor: order.amountMinor,
        currency: order.currency,
        orderId: order.orderId,
        keyId: keyId,
        description: AppConstants.razorpayCheckoutDescription(
          months: months,
          isUpgrade: isUpgrade,
          isRenew: isRenew,
          isFilePlan: isFilePlan,
          includeFilePlan: includeFilePlan,
        ),
        email: user.email,
        contact: user.primaryMobile,
        name: user.displayName,
      );

      if (payment == null) {
        try {
          await AdminCloudFunctions().markPaymentFailed(
            orderId: order.orderId,
            reason: 'cancelled_or_failed',
          );
        } catch (_) {}
        if (mounted) Navigator.of(context).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment cancelled or failed')),
        );
        return;
      }

      final orderId = payment.orderId ?? order.orderId;
      final signature = payment.signature;
      if (signature == null || signature.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing payment signature')),
        );
        return;
      }

      final ok = await state.confirmRazorpaySubscription(
        months: months,
        razorpayOrderId: orderId,
        razorpayPaymentId: payment.paymentId,
        razorpaySignature: signature,
        planType: planType,
      );

      if (mounted) Navigator.of(context).pop();

      if (!mounted) return;
      if (ok) {
        await _showPaymentWelcomeDialog(
          state: state,
          order: order,
          months: months,
          planType: planType,
          includeFilePlan: includeFilePlan,
          isUpgrade: isUpgrade,
          paymentId: payment.paymentId,
          primaryLabel: widget.requiredUpgrade && !isFilePlan
              ? 'Go to vault'
              : 'Continue',
        );
        if (!mounted) return;
        if (widget.requiredUpgrade && !isFilePlan) {
          await openVaultHome(context);
          return;
        }
        if (isFilePlan && widget.renewFilePlan) {
          Navigator.of(context).pop();
          return;
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.errorMessage ?? 'Verification failed'),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', '').replaceFirst(
                    'Bad state: ',
                    '',
                  ),
            ),
          ),
        );
      }
    }
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({
    required this.isCurrent,
    required this.isRenew,
    required this.isUpgrade,
    required this.canBuy,
  });

  final bool isCurrent;
  final bool isRenew;
  final bool isUpgrade;
  final bool canBuy;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color bg;
    final Color fg;

    if (isCurrent) {
      label = 'Subscribed';
      bg = AppColors.teal;
      fg = Colors.white;
    } else if (isRenew) {
      label = 'Renew';
      bg = AppColors.teal.withValues(alpha: 0.15);
      fg = AppColors.teal;
    } else if (isUpgrade) {
      label = 'Upgrade';
      bg = AppColors.amber.withValues(alpha: 0.2);
      fg = AppColors.ink;
    } else if (canBuy) {
      label = 'Subscribe';
      bg = AppColors.foam;
      fg = AppColors.teal;
    } else {
      label = 'Unavailable';
      bg = AppColors.mist.withValues(alpha: 0.35);
      fg = AppColors.slate;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
