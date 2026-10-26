import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/navigation/vault_routes.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';
import 'terms_screen.dart';

/// Splash + vault gate (requirement 1).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final state = context.read<VaultAppState>();
    await state.initialize();
    // Short brand beat only — do not add a long wait on top of boot work.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    if (!state.termsAccepted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TermsScreen()),
      );
      return;
    }

    if (state.user == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    if (AppConstants.isAdminEmail(state.user?.email)) {
      await navigateAfterAuth(context, state);
      return;
    }

    await navigateAfterAuth(context, state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const VaultLogo(size: 96)
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .scale(begin: const Offset(0.8, 0.8)),
                const SizedBox(height: 28),
                Text(
                  AppConstants.appName,
                  style: Theme.of(context).textTheme.displayMedium,
                )
                    .animate()
                    .fadeIn(delay: 200.ms)
                    .slideY(begin: 0.2, end: 0),
                const SizedBox(height: 8),
                Text(
                  AppConstants.appTagline,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 400.ms),
                const SizedBox(height: 48),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.teal,
                  ),
                ).animate().fadeIn(delay: 600.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
