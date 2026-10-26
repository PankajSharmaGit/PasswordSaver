import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';

/// End-to-end encryption terms (requirement 5).
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VaultLogo(size: 56),
                const SizedBox(height: 20),
                Text(
                  'Terms & Conditions',
                  style: Theme.of(context).textTheme.displayMedium,
                ).animate().fadeIn(),
                const SizedBox(height: 8),
                Text(
                  'We protect every user ID and password with end-to-end encryption.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.mist.withValues(alpha: 0.6),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _termsBody,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: _accepted,
                  onChanged: (v) => setState(() => _accepted = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I understand and agree to end-to-end encryption and the terms above.',
                  ),
                  activeColor: AppColors.teal,
                ),
                VaultButton(
                  label: 'Continue',
                  onPressed: _accepted
                      ? () async {
                          await context.read<VaultAppState>().acceptTerms();
                          if (!context.mounted) return;
                          Navigator.of(context).pushReplacementNamed('/login');
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const String _termsBody = '''
1. End-to-end encryption
Your passwords are encrypted on-device using AES-256 before they leave your phone. ${AppConstants.appName} cannot read your plaintext passwords.

2. App PIN & device authentication
An app PIN is required every time you open the vault. Revealing a password may also require biometric or device PIN verification.

3. Account recovery
If you forget your email or lose your device, recovery requires at least two factors: email, primary/secondary mobile, or remembered app PIN.

4. Free trial & subscription
New accounts receive a ${AppConstants.freeTrialDays}-day free trial. After it ends you must subscribe to continue. Paid plans: 3 months ₹100, 6 months ₹180, 12 months ₹350, 24 months ₹650.

5. Screenshots & recording
For your safety, screenshots and screen recording are blocked inside the app. Screen rotation is locked to portrait.

6. Your responsibility
You remain responsible for the accuracy of stored credentials and for keeping your app PIN confidential.

By continuing you consent to secure account authentication, encrypted cloud sync of your vault data, and limited header/footer advertisements.
''';
}
