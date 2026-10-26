import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../presentation/providers/app_state.dart';
import '../../presentation/screens/admin_dashboard_screen.dart';
import '../../presentation/screens/country_selection_screen.dart';
import '../../presentation/screens/pin_lock_screen.dart';
import '../../presentation/screens/subscription_screen.dart';
import '../../presentation/shell/main_shell.dart';

/// After auth: admin → AdminDashboard; else country (if missing) → PIN.
Future<void> navigateAfterAuth(BuildContext context, VaultAppState state) async {
  if (AppConstants.isAdminEmail(state.user?.email)) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      (_) => false,
    );
    return;
  }

  // Splash already loaded the user doc. Skip a second Firestore read.
  if (state.user == null) {
    await state.refreshUserProfile();
    if (!context.mounted) return;
  }

  if (state.user?.hasSelectedCountry != true) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CountrySelectionScreen()),
      (_) => false,
    );
    return;
  }

  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => PinLockScreen(forceCreate: !state.hasPin),
    ),
  );
}

/// Opens dashboard or forces subscription when the free trial / plan has expired.
Future<void> openVaultHome(BuildContext context) async {
  final state = context.read<VaultAppState>();

  if (AppConstants.isAdminEmail(state.user?.email)) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      (_) => false,
    );
    return;
  }

  if (state.user?.isBlocked == true) {
    await state.signOut();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This account has been blocked by admin')),
    );
    return;
  }

  if (state.user?.hasSelectedCountry != true) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CountrySelectionScreen()),
      (_) => false,
    );
    return;
  }

  final needsPlan = state.subscriptionRequired;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => needsPlan
          ? const SubscriptionScreen(requiredUpgrade: true)
          : const MainShell(),
    ),
    (_) => false,
  );

  // Plan status refreshes after the vault is already open.
  unawaited(state.refreshSubscriptionFromFirebase());
}

/// Replaces the current route when access expires while the app is open.
Future<void> redirectIfSubscriptionRequired(BuildContext context) async {
  if (!context.mounted) return;
  final state = context.read<VaultAppState>();
  if (AppConstants.isAdminEmail(state.user?.email)) return;
  if (!state.subscriptionRequired) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => const SubscriptionScreen(requiredUpgrade: true),
    ),
    (_) => false,
  );
}
