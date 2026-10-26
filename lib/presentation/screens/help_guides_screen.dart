import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Shared scrollable help article used by Settings guide pages.
class HelpGuideScreen extends StatelessWidget {
  const HelpGuideScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.sections,
  });

  final String title;
  final String subtitle;
  final List<HelpSection> sections;

  @override
  Widget build(BuildContext context) {
    return VaultBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  for (final section in sections) ...[
                    _HelpSectionCard(section: section),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HelpSection {
  const HelpSection({
    required this.title,
    required this.body,
    this.icon = Icons.info_outline_rounded,
    this.bullets = const [],
  });

  final String title;
  final String body;
  final IconData icon;
  final List<String> bullets;
}

class _HelpSectionCard extends StatelessWidget {
  const _HelpSectionCard({required this.section});

  final HelpSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.mist.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(section.icon, color: AppColors.teal, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 17,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (section.bullets.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final bullet in section.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                        Icons.circle,
                        size: 6,
                        color: AppColors.teal,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bullet,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// How to use PasswordSaver day to day.
class HowToUseAppScreen extends StatelessWidget {
  const HowToUseAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HelpGuideScreen(
      title: 'How to use the app',
      subtitle:
          'Simple steps to save, find, and protect every password and file.',
      sections: const [
        HelpSection(
          icon: Icons.person_add_alt_1_outlined,
          title: '1. Create account & set PIN',
          body:
              'Sign up with your details, accept encryption terms, then set a '
              '${AppConstants.appPinLength}-digit app PIN. This PIN opens your vault '
              'every time and helps protect password reveal.',
          bullets: [
            'Remember your recovery mobile and recovery email — they help if you lose access.',
            'Complete OTP verification from Profile when asked, so recovery stays ready.',
          ],
        ),
        HelpSection(
          icon: Icons.dashboard_outlined,
          title: '2. Dashboard — your vault home',
          body:
              'All saved logins appear here, grouped by service and account group '
              '(for example Email → Company name → accounts).',
          bullets: [
            'Use search to find by title, user ID, group, or service name.',
            'Tap filter chips to show one platform (Banking, Government, etc.).',
            'Tap a credential to view details; reveal password with PIN when required.',
          ],
        ),
        HelpSection(
          icon: Icons.add_circle_outline,
          title: '3. Add a password / login',
          body:
              'Tap Add, choose a service (Email, Banking, Custom, and more), then enter '
              'title, user ID, password, and optional notes or website.',
          bullets: [
            'Use Account group when one service has many accounts (office, personal, client).',
            'You can attach multiple files per password (PDF, image, .env, etc.; max 1 MB each).',
            'Each file counts toward your plan limit; if full, Subscription opens to upgrade.',
          ],
        ),
        HelpSection(
          icon: Icons.folder_open_outlined,
          title: '4. Open attached files',
          body:
              'Open a credential → tap the attachment. Enter PIN to download or open. '
              'Files can stay cached on the device for offline use.',
          bullets: [
            'Free files included with your base / trial plan open after base renew.',
            'Extra files from a file plan need an active file plan; otherwise the app asks you to renew.',
          ],
        ),
        HelpSection(
          icon: Icons.cloud_sync_outlined,
          title: '5. Offline + cloud sync',
          body:
              'You can keep working offline. Changes wait locally, then sync to your '
              'encrypted cloud vault when the network is back.',
          bullets: [
            'Settings → Offline sync to cloud shows pending changes and last sync time.',
            'Tap sync anytime after login when cloud sync is ready.',
          ],
        ),
        HelpSection(
          icon: Icons.security_outlined,
          title: '6. Security controls',
          body:
              'Settings lets you strengthen daily protection without changing how you save passwords.',
          bullets: [
            'Update app PIN anytime (old PIN required).',
            'Turn on “PIN to view passwords” for extra confirm before reveal.',
            'Forgot PIN / lost device uses two-factor recovery.',
            'Screenshots can be blocked; screen stays portrait for safer reading.',
          ],
        ),
        HelpSection(
          icon: Icons.manage_accounts_outlined,
          title: '7. Profile & recovery',
          body:
              'Edit display name, recovery mobile, and recovery email from Profile. '
              'Verify each channel with OTP so account recovery stays reliable.',
        ),
      ],
    );
  }
}

/// Explains base plans, file plans, upgrade, and renew rules.
class SubscriptionPlansGuideScreen extends StatelessWidget {
  const SubscriptionPlansGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HelpGuideScreen(
      title: 'Subscription plans',
      subtitle:
          'How trial, base plans, file add-ons, upgrade, and renew work — in plain language.',
      sections: const [
        HelpSection(
          icon: Icons.card_giftcard_outlined,
          title: 'Free trial',
          body:
              'New users get a ${AppConstants.freeTrialDays}-day free trial with a limited '
              'number of free file attachments. When the trial ends, subscribe to keep full vault access.',
        ),
        HelpSection(
          icon: Icons.all_inclusive,
          title: 'Lifetime free (admin grant)',
          body:
              'If an admin places your account on lifetime free, vault access never expires. '
              'You can still buy a paid plan later if you want a larger file quota.',
        ),
        HelpSection(
          icon: Icons.workspace_premium_outlined,
          title: 'Base subscription plans',
          body:
              'Base plans (3, 6, 12, 24 months) unlock the vault for that period and include '
              'free file slots with each plan. Longer plans usually include more free files.',
          bullets: [
            'Pay securely with UPI, card, or netbanking.',
            'Payment is verified securely before the plan activates.',
            'Prices and file limits can be updated by admin; the app shows the live catalog.',
          ],
        ),
        HelpSection(
          icon: Icons.attach_file_outlined,
          title: 'Optional file plan (add-on)',
          body:
              'Need more than free file slots? Add a file plan for the same duration as your '
              'current base plan. Extra files are added on top of free files (not replacing them).',
          bullets: [
            'While buying base, you can tick “Include file plan” and pay both amounts together.',
            'Or buy the matching file plan later from Subscription after base is active.',
            'File plan duration must match your active base months (e.g. 12 with 12).',
          ],
        ),
        HelpSection(
          icon: Icons.upgrade_rounded,
          title: 'Upgrading base plan',
          body:
              'If you upgrade to a higher plan while some days are left, the new base period '
              'starts from today for the full new length. Remaining days on the old base plan '
              'are not added on top.',
          bullets: [
            'Example: 10 days left on 3-month → upgrade to 12-month → you get a fresh 12 months from today.',
            'If you already have a file plan, its remaining time stays — you can keep using add-on files until that file plan ends.',
            'If you include a new file plan at upgrade checkout, it replaces the old file plan until the new base ends.',
          ],
        ),
        HelpSection(
          icon: Icons.lock_clock_outlined,
          title: 'After file plan expires',
          body:
              'When the file add-on ends, files within your new base free quota stay open. '
              'Files above that free count need a new file plan based on your current upgraded base plan.',
        ),
        HelpSection(
          icon: Icons.restart_alt_rounded,
          title: 'Renew after expiry',
          body:
              'If the base plan expires, the app asks you to subscribe again before using the vault. '
              'Renewing base restores access to free-quota files. Renew the matching file plan to '
              'open add-on files again.',
        ),
        HelpSection(
          icon: Icons.payments_outlined,
          title: 'Where to manage plans',
          body:
              'Open Settings → Subscription plans, or Profile → Upgrade / Manage subscription. '
              'There you can see current status, free vs upgrade file usage, and buy or upgrade.',
        ),
      ],
    );
  }
}

/// Real-life reasons to use PasswordSaver across sectors / fields.
class WhyUseAppScreen extends StatelessWidget {
  const WhyUseAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HelpGuideScreen(
      title: 'Why use this app',
      subtitle:
          'PasswordSaver is useful in every field of life and work — one encrypted place '
          'for IDs, passwords, and important files so you never depend on memory or unsafe notes.',
      sections: const [
        HelpSection(
          icon: Icons.public_outlined,
          title: 'Why it matters for everyone',
          body:
              'Today every person has dozens of logins: email, bank, government, office tools, '
              'shopping, social apps, Wi‑Fi, and devices. Writing them in phone notes, WhatsApp, '
              'or a diary is risky and easy to lose. ${AppConstants.appName} keeps them encrypted, '
              'organized by service, and available offline with sync when you need it.',
          bullets: [
            'One vault instead of sticky notes, screenshots, or reused weak passwords.',
            'PIN + encryption so casual phone access does not expose every login.',
            'Attachments for PDFs, ID scans, .env files, and other proofs next to the login.',
          ],
        ),
        HelpSection(
          icon: Icons.school_outlined,
          title: 'Students & education',
          body:
              'College portals, scholarship sites, exam forms, email, and learning apps all need '
              'separate IDs. Missing one password before a deadline is stressful.',
          bullets: [
            'Store DigiLocker / education portal / result site logins under Government or Custom.',
            'Keep fee receipt PDFs or admit-card files attached to the related credential.',
            'Share less with friends — open only what you need with PIN.',
          ],
        ),
        HelpSection(
          icon: Icons.work_outline_rounded,
          title: 'Jobs, offices & professionals',
          body:
              'Employees juggle email, VPN, HRMS, CRM, project tools, and client portals. '
              'IT often forbids saving passwords in browsers on shared PCs.',
          bullets: [
            'Use Account groups (Client A, Office, Personal) under the same service.',
            'Attach policy PDFs, API keys files, or onboarding docs to the right login.',
            'Safer handoff when changing projects — credentials stay in your private vault.',
          ],
        ),
        HelpSection(
          icon: Icons.account_balance_outlined,
          title: 'Banking & finance',
          body:
              'Net banking, UPI apps, demat, insurance, and loan portals are high-risk if leaked. '
              'A dedicated Banking category keeps them separate from social logins.',
          bullets: [
            'Never store OTPs — only user IDs / passwords / customer IDs you must remember.',
            'Attach policy or statement PDFs only if you choose; they stay encrypted in your vault flow.',
            'PIN before open reduces shoulder-surfing risk in public places.',
          ],
        ),
        HelpSection(
          icon: Icons.account_balance_outlined,
          title: 'Government & public services',
          body:
              'Aadhaar-linked portals, tax filing, PF, passport, municipal apps, and ration / '
              'scheme sites are used rarely — passwords are forgotten exactly when needed.',
          bullets: [
            'Save under Government with clear titles (Income Tax, EPFO, Passport Seva).',
            'Keep acknowledgement PDFs or application numbers in notes / attachments.',
            'Useful for families helping elders manage official logins securely.',
          ],
        ),
        HelpSection(
          icon: Icons.local_hospital_outlined,
          title: 'Healthcare',
          body:
              'Hospital patient portals, lab reports, insurance apps, and pharmacy accounts '
              'contain sensitive personal data.',
          bullets: [
            'Store portal logins separately from social media.',
            'Attach discharge summaries or report PDFs next to the hospital login if needed.',
            'Reduce sharing passwords over SMS when relatives help with appointments.',
          ],
        ),
        HelpSection(
          icon: Icons.storefront_outlined,
          title: 'Business, shops & freelancers',
          body:
              'GST portals, marketplace seller panels (Amazon, etc.), payment gateways, '
              'domain/hosting, and supplier emails are critical for daily sales.',
          bullets: [
            'Custom / Manual service for niche tools (billing software, local CRM).',
            'Group by brand or branch when one person manages many shops.',
            'File plan helps store invoices, NOCs, or .env / config files for sites.',
          ],
        ),
        HelpSection(
          icon: Icons.code_outlined,
          title: 'IT, developers & creators',
          body:
              'GitHub, cloud consoles, hosting panels, app stores, and staging sites multiply '
              'credentials quickly. Browser password managers on shared machines are risky.',
          bullets: [
            'Use GitHub / App Store / Play Store categories plus Custom for servers.',
            'Attach .env or config text files with the related project login.',
            'Offline cache helps when deploying without stable network.',
          ],
        ),
        HelpSection(
          icon: Icons.campaign_outlined,
          title: 'Marketing, social & media',
          body:
              'Teams manage Facebook, Instagram, X, LinkedIn, YouTube, and ad accounts for brands. '
              'Losing one login can stop campaigns.',
          bullets: [
            'One vault entry per brand page with clear titles.',
            'Notes for backup codes or assigned owner names.',
            'PIN gate before reveal when handing a phone to a colleague briefly.',
          ],
        ),
        HelpSection(
          icon: Icons.home_work_outlined,
          title: 'Home, family & daily life',
          body:
              'Wi‑Fi, Netflix, Amazon, mobile device PINs/patterns notes, smart home apps, '
              'and school parent apps belong to everyday life — not only “office work”.',
          bullets: [
            'Mobile Device / System / PC categories for phone and computer logins.',
            'Streaming and shopping accounts stay findable in their own sections.',
            'Elders and family members benefit from one clear place instead of forgotten diaries.',
          ],
        ),
        HelpSection(
          icon: Icons.agriculture_outlined,
          title: 'Farming, field work & travel',
          body:
              'Subsidy portals, co-operative bank apps, transport booking, hotel logins, and '
              'field-force apps are used away from home with weak connectivity.',
          bullets: [
            'Offline vault access when signal is poor; sync when back online.',
            'Government / Banking / Custom covers most rural and travel use cases.',
            'Keep booking PDFs attached so tickets are not lost in gallery clutter.',
          ],
        ),
        HelpSection(
          icon: Icons.gavel_outlined,
          title: 'Legal, compliance & admin staff',
          body:
              'Court e-filing, company ROC / MCA, tender portals, and compliance dashboards '
              'are password-heavy and deadline-driven.',
          bullets: [
            'Clear titles and groups per client or case.',
            'Attach filing acknowledgements next to the portal login.',
            'Encryption supports professional duty of care for client credentials you must hold.',
          ],
        ),
        HelpSection(
          icon: Icons.favorite_outline,
          title: 'Peace of mind',
          body:
              'Whatever your field — study, job, business, farming, healthcare, or home — '
              '${AppConstants.appName} is built so you spend less time remembering and more time '
              'doing real work, without leaving secrets in unsafe places.',
          bullets: [
            'Organized by real-life services you already use.',
            'Plans scale from light personal use to heavier file storage.',
            'If something is unclear, re-read How to use and Subscription plans in Settings.',
          ],
        ),
      ],
    );
  }
}
