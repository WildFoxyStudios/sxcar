import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design token + theme system for Vibra.
///
/// Usage in MaterialApp:
/// ```dart
/// theme: VibraTheme.dark(),
/// ```
class VibraTheme {
  VibraTheme._(); // prevent instantiation

  // ── Color tokens ──────────────────────────────────────────────────────────
  static const Color kAccent = Color(0xFFF4C542); // yellow — used sparingly
  static const Color kBg = Color(0xFF0D0D0D);
  static const Color kSurface = Color(0xFF1A1A1A);
  static const Color kSurfaceElevated = Color(0xFF1F1F1F);
  static const Color kTextPrimary = Color(0xFFE8E8E8);
  static const Color kTextSecondary = Color(0xFF999999);
  static const Color kTextMuted = Color(0xFF666666);
  static const Color kOnline = Color(0xFF44C767); // green online dot
  static const Color kDivider = Color(0xFF2A2A2A);
  static const Color kError = Color(0xFFCF6679);

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

  // ── ThemeData factory ─────────────────────────────────────────────────────
  static ThemeData dark() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: kBg,

      colorScheme: const ColorScheme.dark(
        primary: kAccent,
        secondary: kAccent,
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
        selectedItemColor: kAccent,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusInput),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusInput),
          borderSide: const BorderSide(color: kAccent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: kTextMuted),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccent,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: kAccent),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: kSurfaceElevated,
        selectedColor: kAccent.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: kTextSecondary, fontSize: 12),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusChip),
        ),
      ),

      dividerTheme: const DividerThemeData(color: kDivider, thickness: 1),

      textTheme: GoogleFonts.nunitoTextTheme(ThemeData.dark().textTheme),

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
