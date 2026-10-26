import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// In-app privacy policy (same content as public Play Store URL).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static Future<void> openPublicUrl() async {
    final uri = Uri.parse(AppConstants.privacyPolicyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Privacy Policy',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: openPublicUrl,
                      child: const Text('Open web'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Last updated: 22 August 2026',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.slate,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.mist.withValues(alpha: 0.5),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _body,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.55,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const String _body = '''
PasswordSaver ("we", "us", "our") is an encrypted password and document vault. This Privacy Policy explains how we handle your information when you use the mobile app.

1. Information we collect
• Account: email, display name, sign-in method (email/password or Google), optional mobile numbers for recovery, and country.
• Vault data: usernames, passwords, service names, notes, and attachments you store. Sensitive fields are encrypted on your device before cloud sync.
• Subscription: plan status, expiry, and payment references via Razorpay (we do not store full card/UPI details).
• Device: OS, app version, and crash logs to improve reliability.

2. How we use data
To provide the vault, sync, PIN/biometric unlock, subscriptions, limited ads (AdMob), security, and support. We do not sell your data.

3. Encryption & security
AES-256 on-device encryption. We cannot read your plaintext passwords. Screenshots and screen recording are blocked on supported devices.

4. Third-party services
Firebase (auth, database, functions, storage), Google Sign-In, Razorpay, and Google AdMob. Each provider has its own privacy policy.

5. Sharing
We do not share vault data with other users. We may disclose information if required by law or to protect safety.

6. Retention & deletion
Data is kept while your account is active. Contact us to request deletion. Uninstalling the app removes local data but not cloud backups until deletion is processed.

7. Your choices
Update profile in Settings, manage device permissions, or email us for export/deletion requests.

8. Children
Not intended for users under 13.

9. International users
Non-India users may see USD pricing. Data may be processed in regions used by our cloud providers.

10. Contact
${AppConstants.adminEmail}

Public URL: ${AppConstants.privacyPolicyUrl}
''';
}
