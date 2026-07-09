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

  // ── HALO brand palette — original identity (electric duotone) ────────────
  // Teal + magenta on a blue-black base. See docs/design/identity.md.
  /// Scaffold background — blue-black.
  static const Color kBg = Color(0xFF0B0E14);

  /// Elevated surface (cards, sheets).
  static const Color kSurface = Color(0xFF151A24);

  /// Chip / segmented control background.
  static const Color kChip = Color(0xFF1E2430);

  /// Divider / separator line.
  static const Color kDivider = Color(0xFF2A3140);

  /// Brand primary — teal. Text OVER this MUST be dark (kBg).
  static const Color kBrandPrimary = Color(0xFF00E0C6);

  /// Lighter teal for gradient endpoints / hovers.
  static const Color kBrandPrimaryLight = Color(0xFF33E8D2);

  /// Brand secondary — magenta. The duotone counterpart to the teal primary.
  static const Color kBrandSecondary = Color(0xFFFF3D8B);

  /// Alias: kAccent == kBrandPrimary (keeps existing references compiling).
  static const Color kAccent = kBrandPrimary;

  /// Accent used for the Events feature surfaces (indigo, on-brand).
  static const Color kEventAccent = Color(0xFF6C63FF);

  /// Accent used for the top premium tier badge/border (bright cyan).
  static const Color kTierTop = Color(0xFF00E5FF);

  /// Muted gold used for secondary highlight icons (e.g. active session).
  static const Color kGold = Color(0xFFF4C542);

  /// Primary text — cool white.
  static const Color kText = Color(0xFFEAF6FF);

  /// Alias: kTextPrimary == kText (keeps existing references compiling).
  static const Color kTextPrimary = kText;

  /// Secondary text — cool mid-grey.
  static const Color kTextSecondary = Color(0xFF8A94A6);

  /// Tertiary text — cool dark grey (section footers, counters).
  static const Color kTextTertiary = Color(0xFF5A6373);

  /// Alias: kTextMuted == kTextTertiary (keeps existing references compiling).
  static const Color kTextMuted = kTextTertiary;

  /// Online presence dot — brand success green.
  static const Color kOnline = Color(0xFF2FD07A);

  /// "Pulse" accent (formerly Boost) — kept green for "go/active".
  static const Color kAccentPulse = Color(0xFF2FD07A);

  /// "Glow" accent (formerly Right-Now) — brand magenta for urgency.
  static const Color kAccentGlow = kBrandSecondary;

  /// Badge / danger red.
  static const Color kBadgeRed = Color(0xFFFF4D5E);

  /// Success / positive feedback (snackbar backgrounds, badges).
  static const Color kSuccess = Color(0xFF2FD07A);

  /// Error / danger colour.
  static const Color kError = Color(0xFFFF4D5E);

  /// Elevated surface — slightly lighter than kSurface.
  static const Color kSurfaceElevated = Color(0xFF1E2430);

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
        primary: kBrandPrimary,
        secondary: kBrandSecondary,
        surface: kSurface,
        onPrimary: Colors.black,
        onSecondary: Colors.white,
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
        selectedItemColor: kBrandPrimary,
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
          borderSide: const BorderSide(color: kBrandPrimary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: kTextMuted),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kBrandPrimary,
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
        style: TextButton.styleFrom(foregroundColor: kBrandPrimary),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: kChip,
        selectedColor: kBrandPrimary.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: kTextSecondary, fontSize: 12),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusChip),
        ),
      ),

      dividerTheme: const DividerThemeData(color: kDivider, thickness: 1),

      // Switch: track kBrandPrimary when ON, #4A4A4A when OFF; thumb always white.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return kBrandPrimary;
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
