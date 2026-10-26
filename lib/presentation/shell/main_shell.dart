import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/vault_routes.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../screens/ads_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/device_lock_gate_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';

/// Bottom nav: Home / Settings / Advertisement / Profile (requirement 17).
///
/// When device-lock-on-open is enabled, dashboard is blocked until system
/// PIN / pattern / fingerprint / face succeeds — on entry and after background.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _deviceLocked = false;
  bool _checkedOnEntry = false;
  DateTime? _pausedAt;
  DateTime? _lastHomeBackAt;
  DateTime? _backGuardAt;
  bool _planRedirectScheduled = false;

  static const _homeTabIndex = 0;
  static const _adsTabIndex = 2;
  static const _exitConfirmWindow = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lockOnDashboardEntry();
      _autoSyncOnOpen();
    });
  }

  /// Auto cloud sync when shell opens if offline changes are pending.
  void _autoSyncOnOpen() {
    if (!mounted) return;
    context.read<VaultAppState>().autoSyncIfNeeded();
  }

  /// Always require system lock before dashboard when setting is ON.
  void _lockOnDashboardEntry() {
    if (!mounted || _checkedOnEntry) return;
    _checkedOnEntry = true;
    final app = context.read<VaultAppState>();
    if (app.deviceLockOnOpen) {
      setState(() => _deviceLocked = true);
    }
  }

  /// Other tabs → Home. Home → double back exits the app.
  void _handleBack() {
    final now = DateTime.now();
    // Predictive back can deliver the same press twice. Ignore the duplicate
    // so the first press only shows the message.
    if (_backGuardAt != null &&
        now.difference(_backGuardAt!) < const Duration(milliseconds: 500)) {
      return;
    }
    _backGuardAt = now;

    if (_index != _homeTabIndex) {
      setState(() => _index = _homeTabIndex);
      _lastHomeBackAt = null;
      return;
    }

    final last = _lastHomeBackAt;
    if (last != null && now.difference(last) <= _exitConfirmWindow) {
      SystemNavigator.pop();
      return;
    }

    _lastHomeBackAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: _exitConfirmWindow,
        ),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = context.read<VaultAppState>();

    if (state == AppLifecycleState.resumed) {
      // Retry cloud sync when returning to foreground
      app.autoSyncIfNeeded();
      if (app.subscriptionRequired && mounted) {
        redirectIfSubscriptionRequired(context);
      }
    }

    if (!app.deviceLockOnOpen) return;

    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      // Clear freshness so resume always asks again
      app.deviceLockVerifiedAt = null;
      return;
    }

    if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final away = DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (away.inMilliseconds > 500 && !_deviceLocked) {
        setState(() => _deviceLocked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeId = context.select<VaultAppState, AppThemeId>(
      (state) => state.themeId,
    );
    final subscriptionRequired = context.select<VaultAppState, bool>(
      (state) => state.subscriptionRequired,
    );
    // Read so nav colors refresh when the theme changes.
    themeId.isDark;

    if (subscriptionRequired) {
      if (!_planRedirectScheduled) {
        _planRedirectScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await redirectIfSubscriptionRequired(context);
          if (mounted) _planRedirectScheduled = false;
        });
      }
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_deviceLocked) {
      return DeviceLockGateScreen(
        title: 'Device lock required',
        subtitle:
            'Verify with your phone PIN, pattern, fingerprint, or face to open the vault',
        onUnlocked: () {
          context.read<VaultAppState>().deviceLockVerifiedAt = DateTime.now();
          setState(() => _deviceLocked = false);
          // Sync after unlock so vault is fresh when user sees dashboard
          context.read<VaultAppState>().autoSyncIfNeeded();
        },
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.gradientBottom,
        body: IndexedStack(
          index: _index,
          children: [
            const DashboardScreen(),
            const SettingsScreen(),
            AdsScreen(
              key: const ValueKey('ads_tab'),
              isActive: _index == _adsTabIndex,
            ),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() {
              _index = i;
              if (i != _homeTabIndex) _lastHomeBackAt = null;
            });
            // Refresh unsynced badge when opening Settings
            if (i == 1) context.read<VaultAppState>().refreshSyncStatus();
          },
          backgroundColor: AppColors.gradientBottom,
          indicatorColor: AppColors.foam,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: AppColors.teal),
              label: 'Home',
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: AppColors.teal),
              label: 'Settings',
            ),
            NavigationDestination(
              icon: const Icon(Icons.campaign_outlined),
              selectedIcon: Icon(Icons.campaign, color: AppColors.teal),
              label: 'Ads',
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: AppColors.teal),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
