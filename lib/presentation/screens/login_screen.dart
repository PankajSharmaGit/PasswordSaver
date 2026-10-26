import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/navigation/vault_routes.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import 'admin_dashboard_screen.dart';
import 'reset_password_screen.dart';
import 'signup_screen.dart';

/// Login via Google or email/password with device details (requirement 2).
/// Toggle [Admin login] for admin User ID + password on the same page.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _adminIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _adminMode = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _adminIdCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _emailLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<VaultAppState>();
    final ok = await state.signInEmail(
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      await navigateAfterAuth(context, state);
      return;
    }
    if (state.pendingVaultRecovery != null) {
      await _handleVaultUnlockRecovery(state);
      return;
    }
    _showError(state.errorMessage);
  }

  Future<void> _handleVaultUnlockRecovery(VaultAppState state) async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlock vault'),
        content: const Text(
          'Your login password was changed, so the vault key needs to be '
          'unlocked again.\n\n'
          '• Use app PIN if this account already had PIN recovery set up\n'
          '• Or start a fresh vault (old saved passwords on this account '
          'will not open)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'fresh'),
            child: const Text('Fresh vault'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'pin'),
            child: const Text('Use app PIN'),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == 'cancel') {
      await state.signOut();
      return;
    }

    if (action == 'fresh') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start fresh vault?'),
          content: const Text(
            'Old encrypted passwords for this account will not be readable. '
            'Continue only if you cannot unlock with app PIN.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start fresh'),
            ),
          ],
        ),
      );
      if (!mounted || confirm != true) return;
      final ok = await state.startFreshVaultAfterPasswordReset();
      if (!mounted) return;
      if (ok) {
        await navigateAfterAuth(context, state);
      } else {
        _showError(state.errorMessage);
      }
      return;
    }

    final pinCtrl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter app PIN'),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: AppConstants.appPinLength,
          decoration: const InputDecoration(
            labelText: 'App PIN',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, pinCtrl.text.trim()),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    pinCtrl.dispose();
    if (!mounted || pin == null || pin.isEmpty) return;

    final ok = await state.recoverVaultWithPin(pin);
    if (!mounted) return;
    if (ok) {
      await navigateAfterAuth(context, state);
    } else {
      _showError(state.errorMessage);
    }
  }

  Future<void> _adminLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final resolved = AppConstants.resolveAdminLoginId(_adminIdCtrl.text);
    if (resolved == null) {
      _showError('Invalid admin User ID');
      return;
    }

    final state = context.read<VaultAppState>();
    final ok = await state.signInEmail(resolved, _passwordCtrl.text);
    if (!mounted) return;
    if (!ok) {
      if (state.pendingVaultRecovery != null) {
        await _handleVaultUnlockRecovery(state);
        return;
      }
      _showError(state.errorMessage ?? 'Admin login failed');
      return;
    }
    if (!AppConstants.isAdminEmail(state.user?.email)) {
      await state.signOut();
      if (!mounted) return;
      _showError('This account is not an admin');
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      (_) => false,
    );
  }

  Future<void> _googleLogin() async {
    final state = context.read<VaultAppState>();
    final ok = await state.signInGoogle();
    if (!mounted) return;
    if (ok) {
      await navigateAfterAuth(context, state);
    } else {
      _showError(state.errorMessage);
    }
  }

  void _showError(String? msg) {
    if (msg == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toggleAdminMode() {
    setState(() {
      _adminMode = !_adminMode;
      _passwordCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<VaultAppState>().isLoading;

    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const VaultLogo(size: 64)
                      .animate()
                      .fadeIn()
                      .slideY(begin: -0.15),
                  const SizedBox(height: 24),
                  Text(
                    _adminMode ? 'Admin login' : 'Welcome back',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _adminMode
                        ? 'Sign in with admin User ID and password.'
                        : 'Sign in to unlock your encrypted vault.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  if (_adminMode)
                    TextFormField(
                      controller: _adminIdCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Admin User ID',
                        hintText: 'admin',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Admin User ID is required';
                        }
                        if (AppConstants.resolveAdminLoginId(v) == null) {
                          return 'Invalid admin User ID';
                        }
                        return null;
                      },
                    )
                  else
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Email is required';
                        }
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 8) {
                        return 'Minimum 8 characters';
                      }
                      return null;
                    },
                  ),
                  if (!_adminMode)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ResetPasswordScreen(),
                            ),
                          );
                        },
                        child: const Text('Forgot password?'),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  VaultButton(
                    label: _adminMode ? 'Admin sign in' : 'Sign in',
                    loading: loading,
                    onPressed: _adminMode ? _adminLogin : _emailLogin,
                  ),
                  if (!_adminMode) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: Divider(color: AppColors.mist)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Expanded(child: Divider(color: AppColors.mist)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    VaultButton(
                      label: 'Continue with Google',
                      icon: Icons.g_mobiledata_rounded,
                      isOutlined: true,
                      loading: loading,
                      onPressed: _googleLogin,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'New here?',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SignupScreen(),
                              ),
                            );
                          },
                          child: const Text('Create account'),
                        ),
                      ],
                    ),
                    Center(
                      child: TextButton.icon(
                        onPressed: _toggleAdminMode,
                        icon: Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 18,
                          color: AppColors.teal,
                        ),
                        label: Text(
                          'Admin login',
                          style: TextStyle(
                            color: AppColors.teal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: _toggleAdminMode,
                        child: const Text('Back to user login'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
