import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';

/// Invite friends — share for points; friend install = 1 month free.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<VaultAppState>();
      final months = await state.syncInviteInstallRewards();
      if (!mounted || months <= 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Friend install reward: +$months month'
            '${months > 1 ? 's' : ''} free!',
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Share → +50 points only.
  Future<void> _shareWithFriends() async {
    final state = context.read<VaultAppState>();
    final message = state.buildInviteShareMessage();

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: '${AppConstants.appName} invite',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open share: $e')),
      );
      return;
    }

    if (!mounted) return;
    final ok = await state.rewardInviteSharePoints();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '+${AppConstants.inviteSharePoints} points added '
                  '(${state.invitePoints} total)'
              : state.errorMessage ?? 'Could not add points',
        ),
      ),
    );
  }

  Future<void> _redeemPoints() async {
    final state = context.read<VaultAppState>();
    final ok = await state.redeemInvitePointsForMonth();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '+${AppConstants.inviteBonusMonths} month free unlocked!'
              : state.errorMessage ?? 'Could not redeem',
        ),
      ),
    );
  }

  Future<void> _claimCode() async {
    final state = context.read<VaultAppState>();
    final ok = await state.claimInviteCode(_codeCtrl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Install registered — your friend gets +1 month free'
              : state.errorMessage ?? 'Could not register code',
        ),
      ),
    );
    if (ok) _codeCtrl.clear();
  }

  Future<void> _copyCode() async {
    final code = context.read<VaultAppState>().inviteCode;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultAppState>();
    final expiry = state.user?.subscriptionExpiresAt;
    final points = state.invitePoints;
    final needed = AppConstants.invitePointsPerMonth;
    final progress = (points / needed).clamp(0.0, 1.0);
    final canRedeem = points >= needed;

    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              IconButton(
                alignment: Alignment.centerLeft,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Text(
                'Invite & earn',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Share = ${AppConstants.inviteSharePoints} points. '
                '${AppConstants.invitePointsPerMonth} points = 1 month free. '
                'Friend installs with your code = you get 1 month free.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.forest, AppColors.teal],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your points',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$points / $needed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white24,
                        color: AppColors.amber,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Share once → +${AppConstants.inviteSharePoints} pts\n'
                      'Friend installs your code → +1 month free for you\n'
                      'Shares sent: ${state.inviteSentCount} · '
                      'Installs: ${state.inviteInstallCount}',
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                    if (expiry != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Access until ${expiry.day}/${expiry.month}/${expiry.year}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              VaultButton(
                label: canRedeem
                    ? 'Redeem $needed points → 1 month free'
                    : 'Need ${needed - points} more points to redeem',
                icon: Icons.workspace_premium_outlined,
                onPressed: canRedeem ? _redeemPoints : null,
                loading: state.isLoading,
              ),
              const SizedBox(height: 24),
              Text(
                'Your invite code',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.mist.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.inviteCode,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              letterSpacing: 1.2,
                              color: AppColors.teal,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy code',
                      onPressed: _copyCode,
                      icon: Icon(Icons.copy_rounded, color: AppColors.teal),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              VaultButton(
                label:
                    'Share with friends (+${AppConstants.inviteSharePoints} pts)',
                icon: Icons.ios_share_rounded,
                onPressed: _shareWithFriends,
              ),
              const SizedBox(height: 28),
              Text(
                'Installed with a friend\'s code?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter their code so they get +1 month free for your install.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: InputDecoration(
                  labelText: 'Enter invite code',
                  hintText: 'e.g. PSABCD1234',
                  prefixIcon: const Icon(Icons.card_giftcard_outlined),
                  enabled: !state.inviteCodeClaimed,
                ),
              ),
              const SizedBox(height: 12),
              VaultButton(
                label: state.inviteCodeClaimed
                    ? 'Install already registered'
                    : 'Register install for friend',
                loading: state.isLoading,
                isOutlined: true,
                onPressed: state.inviteCodeClaimed ? null : _claimCode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
