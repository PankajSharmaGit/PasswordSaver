import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/security/screen_security_bootstrap.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/pin_gate.dart';
import 'help_guides_screen.dart';
import 'invite_screen.dart';
import 'login_screen.dart';
import 'pin_lock_screen.dart';
import 'privacy_policy_screen.dart';
import 'recovery_screen.dart';
import 'subscription_screen.dart';

/// Settings: re-verify toggle, PIN update, security (req 8, 10).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultAppState>();

    return VaultBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 6),
            Text(
              'Security controls for your vault',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Text(
              'Appearance',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _SectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      Icon(Icons.palette_outlined, color: AppColors.teal),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Theme',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              state.themeId.description,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: AppThemeId.values.map((id) {
                      final selected = state.themeId == id;
                      final swatches = id.previewColors;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => state.setThemeId(id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 104,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.foam
                                : (AppColors.isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.white.withValues(alpha: 0.55)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? AppColors.teal
                                  : AppColors.mist.withValues(alpha: 0.55),
                              width: selected ? 1.8 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  for (final c in swatches)
                                    Container(
                                      width: 16,
                                      height: 16,
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: BoxDecoration(
                                        color: c,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.mist
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                    ),
                                  if (selected)
                                    Icon(
                                      Icons.check_circle,
                                      size: 16,
                                      color: AppColors.teal,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                id.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.phonelink_lock_outlined),
                  title: const Text('Device lock on open'),
                  subtitle: const Text(
                    'Every time app opens, verify with phone PIN / pattern / fingerprint / face',
                  ),
                  value: state.deviceLockOnOpen,
                  activeThumbColor: AppColors.teal,
                  onChanged: (enabled) async {
                    final ok = await state.setDeviceLockOnOpen(enabled);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? (enabled
                                  ? 'Device lock enabled'
                                  : 'Device lock disabled')
                              : state.errorMessage ?? 'Could not update setting',
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: Text(
                    state.hasPin ? 'Update app PIN' : 'Create app PIN',
                  ),
                  subtitle: Text(
                    state.hasPin
                        ? 'Requires current PIN'
                        : 'Required before viewing any password',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    if (!state.hasPin) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PinLockScreen(
                            forceCreate: true,
                            returnAfterCreate: true,
                          ),
                        ),
                      );
                      return;
                    }
                    await _showUpdatePin(context);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_outlined),
                  title: const Text('PIN to view password'),
                  subtitle: Text(
                    state.reverifyOnView
                        ? 'ON — app PIN required every time you reveal a password'
                        : 'OFF — passwords can be revealed without PIN',
                  ),
                  value: state.reverifyOnView,
                  activeThumbColor: AppColors.teal,
                  onChanged: (enabled) async {
                    // Ensure PIN exists before allowing this security toggle
                    if (!state.hasPin) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PinLockScreen(
                            forceCreate: true,
                            returnAfterCreate: true,
                          ),
                        ),
                      );
                      if (!context.mounted) return;
                      if (!context.read<VaultAppState>().hasPin) return;
                    }

                    final pin = await requirePinToContinue(
                      context,
                      title: 'Enter app PIN',
                      subtitle: enabled
                          ? 'Confirm PIN to enable PIN-on-view'
                          : 'Confirm PIN to disable PIN-on-view',
                    );
                    if (pin == null || !context.mounted) return;

                    final ok = await state.setReverifyOnView(
                      enabled,
                      pin: pin,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? (enabled
                                  ? 'PIN required to view passwords'
                                  : 'PIN no longer required to view passwords')
                              : state.errorMessage ?? 'Could not update setting',
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Forgot PIN / lost device'),
                  subtitle: const Text('Two-factor recovery'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecoveryScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Help & guides',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _SectionCard(
              children: [
                ListTile(
                  leading: Icon(Icons.menu_book_outlined, color: AppColors.teal),
                  title: const Text('How to use the app'),
                  subtitle: const Text('Save passwords, files, sync & security'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HowToUseAppScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.payments_outlined, color: AppColors.teal),
                  title: const Text('How subscription plans work'),
                  subtitle: const Text('Trial, base, file add-on, upgrade & renew'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionPlansGuideScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.public_outlined, color: AppColors.teal),
                  title: const Text('Why use this app'),
                  subtitle: const Text('Real-life use for every field & sector'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WhyUseAppScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Legal',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _SectionCard(
              children: [
                ListTile(
                  leading: Icon(Icons.privacy_tip_outlined, color: AppColors.teal),
                  title: const Text('Privacy Policy'),
                  subtitle: const Text('How we handle your data'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.description_outlined, color: AppColors.teal),
                  title: const Text('Terms & Conditions'),
                  subtitle: const Text('Encryption & subscription terms'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pushNamed('/terms');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Subscription plans'),
                  subtitle: Text(
                    state.user?.isLifetimeFree == true
                        ? 'Lifetime free · no expiry'
                        : state.user?.isTrialActive == true &&
                                state.user!.hasActiveAccess
                            ? 'Free trial active (${AppConstants.freeTrialDays} days)'
                            : 'Manage plan',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.share_outlined, color: AppColors.teal),
                  title: const Text('Share PasswordSaver'),
                  subtitle: const Text('Send the Play Store link'),
                  onTap: () => _shareApp(context),
                ),
                if (AppConstants.inviteFriendsEnabled)
                  ListTile(
                    leading: Icon(Icons.card_giftcard_outlined, color: AppColors.teal),
                    title: const Text('Invite friends'),
                    subtitle: const Text(
                      'Share = 50 pts · 200 pts = 1 month · friend install = 1 month',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const InviteScreen(),
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: Icon(
                    state.firebaseReady
                        ? Icons.cloud_sync_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  title: const Text('Offline sync to cloud'),
                  subtitle: state.firebaseReady
                      ? Text(
                          state.isSyncing
                              ? 'Syncing…'
                              : state.unsyncedCount > 0
                                  ? '${state.unsyncedCount} unsynced change(s) · tap to sync'
                                  : state.lastSyncedAt == null
                                      ? 'Never synced · tap to sync now'
                                      : 'Synced · ${_formatSyncTime(state.lastSyncedAt!)}',
                        )
                      : null,
                  trailing: state.isSyncing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (state.unsyncedCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.coral,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${state.unsyncedCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            const Icon(Icons.sync),
                          ],
                        ),
                  onTap: state.firebaseReady && !state.isSyncing
                      ? () async {
                          state.refreshSyncStatus();
                          final ok = await state.syncNow();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? (state.unsyncedCount == 0
                                        ? 'Cloud sync complete'
                                        : 'Synced · ${state.unsyncedCount} still pending')
                                    : state.errorMessage ?? 'Sync failed',
                              ),
                            ),
                          );
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.screenshot_outlined),
                  title: const Text('Screenshot protection'),
                  subtitle: Text(
                    ScreenSecurityBootstrap.protectionEnabled
                        ? 'Enabled — screenshots blocked'
                        : 'Disabled — screenshots allowed (temporary)',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.screen_lock_portrait_outlined),
                  title: const Text('Screen rotation'),
                  subtitle: const Text('Locked to portrait'),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Encryption'),
                  subtitle: const Text('AES-256-CBC + salted PIN hash'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            VaultButton(
              label: 'Sign out',
              isOutlined: true,
              onPressed: () async {
                await state.signOut();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUpdatePin(BuildContext context) async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update app PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(AppConstants.appPinLength),
              ],
              decoration: const InputDecoration(labelText: 'Current PIN'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(AppConstants.appPinLength),
              ],
              decoration: InputDecoration(
                labelText: 'New PIN (${AppConstants.appPinLength} digits)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(AppConstants.appPinLength),
              ],
              decoration: const InputDecoration(labelText: 'Confirm new PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (newCtrl.text.length != AppConstants.appPinLength ||
                  confirmCtrl.text.length != AppConstants.appPinLength) {
                return;
              }
              if (newCtrl.text != confirmCtrl.text) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (saved != true || !context.mounted) return;
    final state = context.read<VaultAppState>();
    final ok = await state.updateAppPin(oldCtrl.text, newCtrl.text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'PIN updated' : state.errorMessage ?? 'Failed'),
      ),
    );
  }
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.9);
    return Material(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.mist.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// Formats last-sync timestamp for Settings subtitle.
String _formatSyncTime(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}
