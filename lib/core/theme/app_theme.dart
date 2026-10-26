import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Available vault appearance presets.
enum AppThemeId {
  ocean,
  midnight,
  cobalt,
  amber,
  rose,
  graphite,
}

extension AppThemeIdX on AppThemeId {
  String get label {
    switch (this) {
      case AppThemeId.ocean:
        return 'Ocean Teal';
      case AppThemeId.midnight:
        return 'Midnight';
      case AppThemeId.cobalt:
        return 'Cobalt';
      case AppThemeId.amber:
        return 'Amber Gold';
      case AppThemeId.rose:
        return 'Rose Clay';
      case AppThemeId.graphite:
        return 'Graphite';
    }
  }

  String get description {
    switch (this) {
      case AppThemeId.ocean:
        return 'Classic teal vault';
      case AppThemeId.midnight:
        return 'Dark emerald night';
      case AppThemeId.cobalt:
        return 'Cool blue focus';
      case AppThemeId.amber:
        return 'Warm gold accents';
      case AppThemeId.rose:
        return 'Soft clay blush';
      case AppThemeId.graphite:
        return 'Neutral mono slate';
    }
  }

  /// Swatch colors shown in the Settings theme picker.
  List<Color> get previewColors {
    final p = VaultPalette.of(this);
    return [p.teal, p.foam, p.amber];
  }

  bool get isDark => this == AppThemeId.midnight || this == AppThemeId.graphite;

  static AppThemeId fromStorage(String? raw) {
    return AppThemeId.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AppThemeId.cobalt,
    );
  }
}

/// Full color set for one appearance.
class VaultPalette {
  const VaultPalette({
    required this.ink,
    required this.forest,
    required this.teal,
    required this.mint,
    required this.foam,
    required this.sand,
    required this.amber,
    required this.coral,
    required this.slate,
    required this.mist,
    required this.gradientTop,
    required this.gradientMid,
    required this.gradientBottom,
    required this.isDark,
  });

  final Color ink;
  final Color forest;
  final Color teal;
  final Color mint;
  final Color foam;
  final Color sand;
  final Color amber;
  final Color coral;
  final Color slate;
  final Color mist;
  final Color gradientTop;
  final Color gradientMid;
  final Color gradientBottom;
  final bool isDark;

  static VaultPalette of(AppThemeId id) {
    switch (id) {
      case AppThemeId.ocean:
        return const VaultPalette(
          ink: Color(0xFF0B1F1A),
          forest: Color(0xFF0F3D34),
          teal: Color(0xFF1A6B5C),
          mint: Color(0xFF3D9B84),
          foam: Color(0xFFE8F5F1),
          sand: Color(0xFFF7F3EC),
          amber: Color(0xFFD4A017),
          coral: Color(0xFFC45C4A),
          slate: Color(0xFF4A5C57),
          mist: Color(0xFFB8CBC4),
          gradientTop: Color(0xFFF7F3EC),
          gradientMid: Color(0xFFE8F5F1),
          gradientBottom: Color(0xFFD5EBE3),
          isDark: false,
        );
      case AppThemeId.midnight:
        return const VaultPalette(
          ink: Color(0xFFE8F0ED),
          forest: Color(0xFF0A1612),
          teal: Color(0xFF2BB89A),
          mint: Color(0xFF1E8F75),
          foam: Color(0xFF15241F),
          sand: Color(0xFF0E1613),
          amber: Color(0xFFE0B84A),
          coral: Color(0xFFE07A6A),
          slate: Color(0xFF9BB0A8),
          mist: Color(0xFF3A4F47),
          gradientTop: Color(0xFF0E1613),
          gradientMid: Color(0xFF12201B),
          gradientBottom: Color(0xFF0A2A22),
          isDark: true,
        );
      case AppThemeId.cobalt:
        return const VaultPalette(
          ink: Color(0xFF0C1A2A),
          forest: Color(0xFF0F2A4A),
          teal: Color(0xFF1E5FAF),
          mint: Color(0xFF4A8FD4),
          foam: Color(0xFFE8F1FA),
          sand: Color(0xFFF2F6FA),
          amber: Color(0xFFD98B2B),
          coral: Color(0xFFC45C4A),
          slate: Color(0xFF4A5C6E),
          mist: Color(0xFFB0C0D0),
          gradientTop: Color(0xFFF2F6FA),
          gradientMid: Color(0xFFE8F1FA),
          gradientBottom: Color(0xFFD0E2F5),
          isDark: false,
        );
      case AppThemeId.amber:
        return const VaultPalette(
          ink: Color(0xFF1A1408),
          forest: Color(0xFF3D2E0A),
          teal: Color(0xFFB8860B),
          mint: Color(0xFFD4A84B),
          foam: Color(0xFFFAF4E6),
          sand: Color(0xFFFFFBF2),
          amber: Color(0xFFE6A817),
          coral: Color(0xFFB85C38),
          slate: Color(0xFF5C5346),
          mist: Color(0xFFD4C9B0),
          gradientTop: Color(0xFFFFFBF2),
          gradientMid: Color(0xFFFAF4E6),
          gradientBottom: Color(0xFFF0E4C8),
          isDark: false,
        );
      case AppThemeId.rose:
        return const VaultPalette(
          ink: Color(0xFF1F1216),
          forest: Color(0xFF4A2430),
          teal: Color(0xFFB85A6E),
          mint: Color(0xFFD48A9A),
          foam: Color(0xFFF9EEF1),
          sand: Color(0xFFFCF7F8),
          amber: Color(0xFFC9A227),
          coral: Color(0xFFA84545),
          slate: Color(0xFF5C4A50),
          mist: Color(0xFFD4B8C0),
          gradientTop: Color(0xFFFCF7F8),
          gradientMid: Color(0xFFF9EEF1),
          gradientBottom: Color(0xFFF0D8E0),
          isDark: false,
        );
      case AppThemeId.graphite:
        return const VaultPalette(
          ink: Color(0xFFE8EAEB),
          forest: Color(0xFF121416),
          teal: Color(0xFF8A9AA8),
          mint: Color(0xFF6B7C8A),
          foam: Color(0xFF1C1F22),
          sand: Color(0xFF141618),
          amber: Color(0xFFC4A35A),
          coral: Color(0xFFD07060),
          slate: Color(0xFF9AA3AB),
          mist: Color(0xFF3A4046),
          gradientTop: Color(0xFF141618),
          gradientMid: Color(0xFF1A1D20),
          gradientBottom: Color(0xFF22262A),
          isDark: true,
        );
    }
  }
}

/// Mutable design tokens — updated when the user picks a theme.
///
/// Existing screens keep using `AppColors.teal` etc.; [apply] refreshes
/// these values whenever [VaultAppState.setThemeId] runs.
class AppColors {
  AppColors._();

  static Color ink = const Color(0xFF0C1A2A);
  static Color forest = const Color(0xFF0F2A4A);
  static Color teal = const Color(0xFF1E5FAF);
  static Color mint = const Color(0xFF4A8FD4);
  static Color foam = const Color(0xFFE8F1FA);
  static Color sand = const Color(0xFFF2F6FA);
  static Color amber = const Color(0xFFD98B2B);
  static Color coral = const Color(0xFFC45C4A);
  static Color slate = const Color(0xFF4A5C6E);
  static Color mist = const Color(0xFFB0C0D0);
  static Color gradientTop = const Color(0xFFF2F6FA);
  static Color gradientMid = const Color(0xFFE8F1FA);
  static Color gradientBottom = const Color(0xFFD0E2F5);
  static bool isDark = false;

  /// Copies [palette] into the static tokens used across the UI.
  static void apply(VaultPalette palette) {
    ink = palette.ink;
    forest = palette.forest;
    teal = palette.teal;
    mint = palette.mint;
    foam = palette.foam;
    sand = palette.sand;
    amber = palette.amber;
    coral = palette.coral;
    slate = palette.slate;
    mist = palette.mist;
    gradientTop = palette.gradientTop;
    gradientMid = palette.gradientMid;
    gradientBottom = palette.gradientBottom;
    isDark = palette.isDark;
  }
}

/// Builds Material theme for the selected [themeId].
ThemeData buildAppTheme(AppThemeId themeId) {
  final palette = VaultPalette.of(themeId);
  AppColors.apply(palette);

  final brightness = palette.isDark ? Brightness.dark : Brightness.light;
  final cardFill = palette.isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.white.withValues(alpha: 0.9);
  final inputFill = palette.isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.85);

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: palette.gradientBottom,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: palette.teal,
      onPrimary: palette.isDark ? palette.sand : Colors.white,
      secondary: palette.amber,
      onSecondary: palette.ink,
      surface: palette.foam,
      onSurface: palette.ink,
      error: palette.coral,
      onError: Colors.white,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.fraunces(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: palette.ink,
        height: 1.1,
      ),
      displayMedium: GoogleFonts.fraunces(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: palette.ink,
      ),
      headlineMedium: GoogleFonts.fraunces(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
      titleLarge: GoogleFonts.dmSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
      bodyLarge: GoogleFonts.dmSans(
        fontSize: 16,
        color: palette.slate,
        height: 1.45,
      ),
      bodyMedium: GoogleFonts.dmSans(
        fontSize: 14,
        color: palette.slate,
        height: 1.4,
      ),
      labelLarge: GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.fraunces(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
      iconTheme: IconThemeData(color: palette.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.mist.withValues(alpha: 0.6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.mist.withValues(alpha: 0.6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.teal, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.coral),
      ),
      labelStyle: GoogleFonts.dmSans(color: palette.slate),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.teal,
        foregroundColor: palette.isDark ? palette.sand : Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle:
            GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.teal,
        side: BorderSide(color: palette.teal, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    cardTheme: CardThemeData(
      color: cardFill,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.mist.withValues(alpha: 0.5)),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: palette.isDark ? palette.foam : Colors.white,
      selectedItemColor: palette.teal,
      unselectedItemColor: palette.slate,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.isDark ? palette.foam : Colors.white,
      indicatorColor: palette.foam,
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.forest,
      contentTextStyle: GoogleFonts.dmSans(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerColor: palette.mist.withValues(alpha: 0.45),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.isDark ? palette.foam : Colors.white,
      titleTextStyle: GoogleFonts.fraunces(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
    ),
  );
}
