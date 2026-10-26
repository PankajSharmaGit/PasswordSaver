import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/ads/mobile_ads_bootstrap.dart';
import 'core/constants/app_constants.dart';
import 'core/security/biometric_service.dart';
import 'core/security/device_info_service.dart';
import 'core/security/screen_security_bootstrap.dart';
import 'core/security/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'data/local/hive_boxes.dart';
import 'data/local/hive_credential_store.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/credential_repository_impl.dart';
import 'data/repositories/pin_subscription_repository_impl.dart';
import 'firebase_options.dart';
import 'presentation/providers/app_state.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/privacy_policy_screen.dart';
import 'presentation/screens/terms_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only (requirement 20)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Offline vault (Hive) — works without network
  await HiveBoxes.init();

  // Firebase is required for auth & cloud sync
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseAvailability.isAvailable = true;
  } catch (e, st) {
    FirebaseAvailability.isAvailable = false;
    debugPrint('Firebase init failed: $e\n$st');
  }

  // Screenshot block should not hold the first frame.
  unawaited(ScreenSecurityBootstrap.enable());

  final storage = SecureStorageService();
  // Apply saved theme before first frame so splash matches preference
  final savedTheme =
      AppThemeIdX.fromStorage(await storage.getAppThemeId());
  AppColors.apply(VaultPalette.of(savedTheme));

  if (!FirebaseAvailability.isAvailable) {
    runApp(const _FirebaseRequiredApp());
    return;
  }

  final hiveStore = HiveCredentialStore();
  final authRepo = AuthRepositoryImpl(
    storage: storage,
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
  );
  final credRepo = CredentialRepositoryImpl(
    hiveStore: hiveStore,
    firestore: FirebaseFirestore.instance,
  );
  final pinRepo = PinRepositoryImpl(
    storage: storage,
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
  );
  final subRepo = SubscriptionRepositoryImpl(
    firestore: FirebaseFirestore.instance,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => VaultAppState(
            authRepository: authRepo,
            credentialRepository: credRepo,
            pinRepository: pinRepo,
            subscriptionRepository: subRepo,
            storage: storage,
            biometricService: BiometricService(),
            deviceInfoService: DeviceInfoService(),
            initialThemeId: savedTheme,
          ),
        ),
      ],
      child: const PasswordSaverApp(),
    ),
  );

  // AdMob init often takes several seconds — start after the UI is up.
  if (MobileAdsBootstrap.isSupported) {
    unawaited(() async {
      try {
        await MobileAdsBootstrap.ensureInitialized();
      } catch (_) {}
    }());
  }
}

/// Shown when Firebase cannot initialize (missing config / wrong platform).
class _FirebaseRequiredApp extends StatelessWidget {
  const _FirebaseRequiredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '${AppConstants.appName} could not start cloud services.\n\n'
              'Please reinstall the app or contact support.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class PasswordSaverApp extends StatelessWidget {
  const PasswordSaverApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final themeId = context.select<VaultAppState, AppThemeId>(
      (state) => state.themeId,
    );
    final isDark = themeId.isDark;

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(themeId),
      builder: (context, child) {
        return _StatusBarStyle(
          isDark: isDark,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/terms': (_) => const TermsScreen(),
        '/privacy': (_) => const PrivacyPolicyScreen(),
      },
    );
  }
}

class _StatusBarStyle extends StatefulWidget {
  const _StatusBarStyle({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  State<_StatusBarStyle> createState() => _StatusBarStyleState();
}

class _StatusBarStyleState extends State<_StatusBarStyle> {
  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(_StatusBarStyle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) _apply();
  }

  void _apply() {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            widget.isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: widget.isDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
