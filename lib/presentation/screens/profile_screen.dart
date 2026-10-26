import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/profile/recovery_otp_functions.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import 'edit_profile_screen.dart';
import 'invite_screen.dart';
import 'subscription_screen.dart';

/// Profile tab (requirement 17).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static final _dateFmt = DateFormat('dd MMM yyyy');

  String _fmt(DateTime? d) => d == null ? '—' : _dateFmt.format(d.toLocal());

  String _countryLabel(AppUser user) {
    final name = user.countryName?.trim();
    final code = user.countryCode?.trim().toUpperCase();
    if (name != null && name.isNotEmpty) {
      if (code != null && code.isNotEmpty) return '$name ($code)';
      return name;
    }
    if (code != null && code.isNotEmpty) return code;
    return 'Not selected';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<VaultAppState>().refreshUserProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultAppState>();
    final user = state.user;
    if (user == null) {
      return const Center(child: Text('Not signed in'));
    }

    final trialStart = user.effectiveTrialStartedAt;
    final expires = user.effectiveExpiresAt;
    final expired = !user.hasActiveAccess;

    return VaultBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Profile',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const EditProfileScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.forest, AppColors.teal],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      user.displayName.isNotEmpty
                          ? user.displayName[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: Colors.white),
                        ),
                        Text(
                          user.email,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '@${user.userId}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _RecoveryTile(
              icon: Icons.phone_outlined,
              label: 'Recovery mobile number',
              value: user.primaryMobile?.trim().isNotEmpty == true
                  ? user.primaryMobile!
                  : '—',
              verified: user.isRecoveryMobileVerified,
              canVerify: (user.primaryMobile ?? '').trim().isNotEmpty &&
                  !user.primaryMobileVerified,
              onVerify: () => _verifyFromProfile(
                context,
                channel: 'mobile',
                target: user.primaryMobile!.trim(),
                title: 'Verify recovery mobile',
              ),
            ),
            _RecoveryTile(
              icon: Icons.mark_email_read_outlined,
              label: 'Recovery email id',
              value: user.recoveryEmail?.trim().isNotEmpty == true
                  ? user.recoveryEmail!
                  : '—',
              verified: user.isRecoveryEmailVerified,
              canVerify: (user.recoveryEmail ?? '').trim().isNotEmpty &&
                  !user.recoveryEmailVerified,
              onVerify: () => _verifyFromProfile(
                context,
                channel: 'email',
                target: user.recoveryEmail!.trim(),
                title: 'Verify recovery email',
              ),
            ),
            _InfoTile(
              icon: Icons.verified_outlined,
              label: 'Login email verified',
              value: user.emailVerified ? 'Yes' : 'Pending',
            ),
            _InfoTile(
              icon: Icons.public_outlined,
              label: 'Country',
              value: _countryLabel(user),
            ),
            _InfoTile(
              icon: Icons.devices_outlined,
              label: 'Last device',
              value: [
                user.deviceDetails['brand'] ??
                    user.deviceDetails['platform'] ??
                    '',
                user.deviceDetails['model'] ?? '',
              ].join(' ').trim().isEmpty
                  ? '—'
                  : [
                      user.deviceDetails['brand'] ??
                          user.deviceDetails['platform'] ??
                          '',
                      user.deviceDetails['model'] ?? '',
                    ].join(' ').trim(),
            ),
            _InfoTile(
              icon: Icons.workspace_premium_outlined,
              label: 'Subscription plan',
              value: user.planStatusLabel,
            ),
            _InfoTile(
              icon: Icons.play_circle_outline,
              label: 'Free trial started',
              value: _fmt(trialStart),
            ),
            _InfoTile(
              icon: expired
                  ? Icons.event_busy_outlined
                  : Icons.event_available_outlined,
              label: expired ? 'Last expire date' : 'Expires on',
              value: _fmt(expires),
            ),
            if (expired)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Your plan has expired. Upgrade now to continue.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.coral,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            if (AppConstants.inviteFriendsEnabled) ...[
              const SizedBox(height: 16),
              VaultButton(
                label: 'Invite friends · points & free month',
                icon: Icons.card_giftcard_outlined,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const InviteScreen()),
                  );
                },
              ),
            ],
            const SizedBox(height: 10),
            VaultButton(
              label: 'Share PasswordSaver',
              icon: Icons.share_outlined,
              isOutlined: true,
              onPressed: () => _shareApp(context),
            ),
            const SizedBox(height: 10),
            VaultButton(
              label: expired ? 'Upgrade now' : 'Manage subscription',
              isOutlined: !expired,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SubscriptionScreen(
                      requiredUpgrade: expired,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareApp(BuildContext context) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${AppConstants.appName} — encrypted vault for passwords and documents.\n${AppConstants.playStoreUrl}',
          subject: AppConstants.appName,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open share: $e')),
      );
    }
  }

  Future<void> _verifyFromProfile(
    BuildContext context, {
    required String channel,
    required String target,
    required String title,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileOtpSheet(
        channel: channel,
        target: target,
        title: title,
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<VaultAppState>().refreshUserProfile();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verified successfully')),
        );
      }
    }
  }
}

class _RecoveryTile extends StatelessWidget {
  const _RecoveryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.verified,
    required this.canVerify,
    required this.onVerify,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool verified;
  final bool canVerify;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.mist.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                if (verified)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.verified, size: 16, color: AppColors.teal),
                        const SizedBox(width: 4),
                        Text(
                          'Verified',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.teal,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (canVerify)
            TextButton(
              onPressed: onVerify,
              child: const Text('Verify'),
            ),
        ],
      ),
    );
  }
}

class _ProfileOtpSheet extends StatefulWidget {
  const _ProfileOtpSheet({
    required this.channel,
    required this.target,
    required this.title,
  });

  final String channel;
  final String target;
  final String title;

  @override
  State<_ProfileOtpSheet> createState() => _ProfileOtpSheetState();
}

class _ProfileOtpSheetState extends State<_ProfileOtpSheet> {
  final _otpCtrl = TextEditingController();
  final _otpApi = RecoveryOtpFunctions();
  bool _busy = false;
  String? _debugOtp;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _otpApi.sendOtp(
        channel: widget.channel,
        target: widget.target,
      );
      if (!mounted) return;
      setState(() {
        _debugOtp = result.debugOtp;
        if (result.debugOtp != null) _otpCtrl.text = result.debugOtp!;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _otpApi.verifyOtp(
        channel: widget.channel,
        target: widget.target,
        otp: otp,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('OTP for ${widget.target}'),
            if (_debugOtp != null) ...[
              const SizedBox(height: 8),
              Text(
                'Test OTP: $_debugOtp',
                style: TextStyle(
                  color: AppColors.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '6-digit OTP',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: AppColors.coral)),
            ],
            const SizedBox(height: 14),
            VaultButton(
              label: 'Verify OTP',
              loading: _busy,
              onPressed: _busy ? null : _verify,
            ),
            TextButton(
              onPressed: _busy ? null : _send,
              child: const Text('Resend OTP'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.mist.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
