import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';

/// Password reset via Firebase email (requirement 4).
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  Timer? _bannerTimer;
  bool _showSentBanner = false;
  String? _sentToEmail;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _showSentMessage(String email) {
    _bannerTimer?.cancel();
    setState(() {
      _showSentBanner = true;
      _sentToEmail = email;
    });
    _bannerTimer = Timer(const Duration(minutes: 2), () {
      if (!mounted) return;
      setState(() {
        _showSentBanner = false;
        _sentToEmail = null;
      });
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final state = context.read<VaultAppState>();
    final ok = await state.resetPassword(email);
    if (!mounted) return;
    if (ok) {
      _showSentMessage(email);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.errorMessage ?? 'Failed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<VaultAppState>().isLoading;

    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Text(
                    'Reset password',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We will email a secure reset link to your registered address.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (_showSentBanner) ...[
                    const SizedBox(height: 20),
                    _SentMailBanner(email: _sentToEmail ?? ''),
                  ],
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) =>
                        (v == null || !v.contains('@'))
                            ? 'Valid email required'
                            : null,
                  ),
                  const SizedBox(height: 24),
                  VaultButton(
                    label: 'Send reset link',
                    loading: loading,
                    onPressed: _submit,
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

class _SentMailBanner extends StatelessWidget {
  const _SentMailBanner({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_email_read_outlined, color: AppColors.teal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reset link sent',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Check your inbox for $email.\n'
            'If you do not see it, also check Spam / Junk / Promotions.\n'
            'This message stays for 2 minutes.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}
