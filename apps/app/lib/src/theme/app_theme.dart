import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design token + theme system for Vibra — v3 (Grindr-parity tokens).
///
/// Usage in MaterialApp:
/// ```dart
/// theme: VibraTheme.dark(),
/// ```
class VibraTheme {
  VibraTheme._(); // prevent instantiation

  // ── Color tokens (verbatim from Global Constraints) ──────────────────────
  /// Pure black scaffold background.
  static const Color kBg = Color(0xFF000000);

  /// Elevated surface (cards, sheets).
  static const Color kSurface = Color(0xFF1A1A1A);

  /// Chip / segmented control background.
  static const Color kChip = Color(0xFF2A2A2A);

  /// Divider / separator line.
  static const Color kDivider = Color(0xFF333333);

  /// Primary yellow accent — text OVER this MUST be black.
  static const Color kYellow = Color(0xFFFFCC00);

  /// Lighter yellow used for gradient endpoints.
  static const Color kYellowLight = Color(0xFFFFD633);

  /// Alias: kAccent == kYellow (keeps existing references compiling).
  static const Color kAccent = kYellow;

  /// Primary text — white.
  static const Color kText = Color(0xFFFFFFFF);

  /// Alias: kTextPrimary == kText (keeps existing references compiling).
  static const Color kTextPrimary = kText;

  /// Secondary text — mid-grey.
  static const Color kTextSecondary = Color(0xFF8E8E8E);

  /// Tertiary text — dark grey (section footers, counters).
  static const Color kTextTertiary = Color(0xFF666666);

  /// Alias: kTextMuted == kTextTertiary (keeps existing references compiling).
  static const Color kTextMuted = kTextTertiary;

  /// Online presence dot.
  static const Color kOnline = Color(0xFF1BD75E);

  /// Boost feature accent.
  static const Color kBoost = Color(0xFF26D944);

  /// Right-Now feature accent.
  static const Color kRightNow = Color(0xFF9B51E0);

  /// Badge / error red.
  static const Color kBadgeRed = Color(0xFFFF3B30);

  /// Success / positive feedback (snackbar backgrounds, badges).
  static const Color kSuccess = Color(0xFF2E7D32);

  /// Error colour (kept for theme).
  static const Color kError = Color(0xFFCF6679);

  /// Elevated surface — kept for backward compat; same as kSurface.
  static const Color kSurfaceElevated = Color(0xFF1F1F1F);

  // ── Spacing / radius constants ────────────────────────────────────────────
  static const double kRadiusCard = 12.0;
  static const double kRadiusInput = 10.0;
  static const double kRadiusChip = 20.0;
  static const double kPadPage = 16.0;
  static const double kPadCard = 12.0;

  // ── Text styles ───────────────────────────────────────────────────────────
  /// Profile display name — bold 18 sp, primary text color.
  static TextStyle get displayName => const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 18,
        color: kTextPrimary,
      );

  /// Secondary body copy — 13 sp, muted text color.
  static TextStyle get bodySecondary => const TextStyle(
        fontSize: 13,
        color: kTextSecondary,
      );

  /// Chip label — 12 sp, secondary text color.
  static TextStyle get labelChip => const TextStyle(
        fontSize: 12,
        color: kTextSecondary,
      );

  /// Button label — bold 14 sp, black (rendered on accent background).
  static TextStyle get labelButton => const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: Colors.black,
      );

  /// Section header — 13 sp, CAPS, letter-spacing 1.2, kTextSecondary.
  static TextStyle get sectionHeader => const TextStyle(
        fontSize: 13,
        color: kTextSecondary,
        letterSpacing: 1.2,
      );

  // ── ThemeData factory ─────────────────────────────────────────────────────
  static ThemeData dark() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: kBg,

      colorScheme: const ColorScheme.dark(
        primary: kYellow,
        secondary: kYellow,
        surface: kSurface,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: kTextPrimary,
        error: kError,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: kBg,
        elevation: 0,
        foregroundColor: kTextPrimary,
        titleTextStyle: TextStyle(
          color: kTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: kBg,
        selectedItemColor: kYellow,
        unselectedItemColor: Color(0xFF777777),
        type: BottomNavigationBarType.fixed,
      ),

      cardTheme: CardThemeData(
        color: kSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusCard),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurfaceElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusInput),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusInput),
          borderSide: const BorderSide(color: kYellow, width: 1.5),
        ),
        hintStyle: const TextStyle(color: kTextMuted),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kYellow,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: kYellow),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: kChip,
        selectedColor: kYellow.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: kTextSecondary, fontSize: 12),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusChip),
        ),
      ),

      dividerTheme: const DividerThemeData(color: kDivider, thickness: 1),

      // Switch: track kYellow when ON, #4A4A4A when OFF; thumb always white.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return kYellow;
          return const Color(0xFF4A4A4A);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),

      snackBarTheme: const SnackBarThemeData(
        backgroundColor: kSurfaceElevated,
        contentTextStyle: TextStyle(color: kTextPrimary),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
