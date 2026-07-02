import 'package:flutter/material.dart';

/// Centralized design tokens for the admin console.
/// Accent colour: #F4C542 (Vibra yellow-gold).
abstract final class AdminTheme {
  // ── Palette ─────────────────────────────────────────────────────────────────
  static const Color kBg        = Color(0xFF0F0F0F); // canvas
  static const Color kSurface   = Color(0xFF1A1A1A); // nav rail, app bar
  static const Color kCard      = Color(0xFF1E1E1E); // cards
  static const Color kBorder    = Color(0xFF2A2A2A); // dividers, card borders
  static const Color kAccent    = Color(0xFFF4C542); // primary / yellow-gold
  static const Color kText      = Color(0xFFE8E8E8); // primary text
  static const Color kMuted     = Color(0xFF7A7A7A); // secondary text
  static const Color kGreen     = Color(0xFF22C55E);
  static const Color kRed       = Color(0xFFEF4444);
  static const Color kOrange    = Color(0xFFF97316);
  static const Color kBlue      = Color(0xFF3B82F6);
  static const Color kAccentBg  = Color(0xFF2E2A14); // subtle accent surface

  // ── Typography helpers ───────────────────────────────────────────────────────
  static TextStyle get headlineMedium => const TextStyle(
    color: kText,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static TextStyle get titleMedium => const TextStyle(
    color: kText,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get bodySmall => const TextStyle(
    color: kMuted,
    fontSize: 12,
  );

  static TextStyle get tableHeader => const TextStyle(
    color: kMuted,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
  );

  // ── ThemeData ────────────────────────────────────────────────────────────────
  static ThemeData build() {
    const cs = ColorScheme(
      brightness: Brightness.dark,
      primary:              kAccent,
      onPrimary:            Color(0xFF1A1400),
      primaryContainer:     kAccentBg,
      onPrimaryContainer:   kAccent,
      secondary:            kAccent,
      onSecondary:          Color(0xFF1A1400),
      secondaryContainer:   kAccentBg,
      onSecondaryContainer: kAccent,
      tertiary:             kGreen,
      onTertiary:           Colors.white,
      tertiaryContainer:    Color(0xFF1A2E1A),
      onTertiaryContainer:  kGreen,
      error:                kRed,
      onError:              Colors.white,
      errorContainer:       Color(0xFF2A1414),
      onErrorContainer:     kRed,
      surface:              kSurface,
      onSurface:            kText,
      surfaceContainerHighest: kCard,
      onSurfaceVariant:     kMuted,
      outline:              kBorder,
      outlineVariant:       Color(0xFF222222),
      shadow:               Colors.black,
      scrim:                Colors.black87,
      inverseSurface:       kText,
      onInverseSurface:     kBg,
      inversePrimary:       Color(0xFF8A6E00),
      surfaceTint:          Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: kBg,
      dividerColor: kBorder,

      // ── Text ──────────────────────────────────────────────────────────────
      textTheme: const TextTheme(
        displayLarge:   TextStyle(color: kText, fontWeight: FontWeight.w700),
        displayMedium:  TextStyle(color: kText, fontWeight: FontWeight.w600),
        displaySmall:   TextStyle(color: kText, fontWeight: FontWeight.w600),
        headlineLarge:  TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 30),
        headlineMedium: TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 22),
        headlineSmall:  TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 18),
        titleLarge:     TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 17),
        titleMedium:    TextStyle(color: kText, fontWeight: FontWeight.w500, fontSize: 15),
        titleSmall:     TextStyle(color: kMuted, fontWeight: FontWeight.w500, fontSize: 13),
        bodyLarge:      TextStyle(color: kText, fontSize: 15),
        bodyMedium:     TextStyle(color: kText, fontSize: 14),
        bodySmall:      TextStyle(color: kMuted, fontSize: 12),
        labelLarge:     TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14),
        labelMedium:    TextStyle(color: kMuted, fontWeight: FontWeight.w500, fontSize: 12),
        labelSmall:     TextStyle(color: kMuted, fontWeight: FontWeight.w500, fontSize: 11),
      ),

      // ── Cards ─────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: kCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: kBorder),
        ),
      ),

      // ── Navigation rail ───────────────────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: kSurface,
        selectedIconTheme: const IconThemeData(color: kAccent, size: 22),
        unselectedIconTheme: const IconThemeData(color: kMuted, size: 22),
        selectedLabelTextStyle: const TextStyle(
          color: kAccent,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelTextStyle: const TextStyle(color: kMuted, fontSize: 13),
        indicatorColor: kAccent.withValues(alpha: 0.15),
      ),

      // ── Input / Form ──────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurface,
        hintStyle: const TextStyle(color: kMuted, fontSize: 14),
        labelStyle: const TextStyle(color: kMuted, fontSize: 14),
        prefixIconColor: kMuted,
        suffixIconColor: kMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kRed, width: 1.5),
        ),
      ),

      // ── Buttons ───────────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kAccent,
          foregroundColor: const Color(0xFF1A1400),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kAccent,
          side: const BorderSide(color: kBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: kAccent),
      ),

      // ── Switch ────────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? kAccent : kMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
            ? kAccent.withValues(alpha: 0.35)
            : kBorder),
      ),

      // ── AppBar ────────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: kSurface,
        foregroundColor: kText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: kText,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),

      // ── Dialogs ───────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: kSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: kText,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kBorder),
        ),
      ),

      // ── SnackBar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: kCard,
        contentTextStyle: const TextStyle(color: kText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Progress ──────────────────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAccent),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(color: kBorder, thickness: 1, space: 1),

      // ── ListTile ──────────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        textColor: kText,
        iconColor: kMuted,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // ── Popup menu ────────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: kSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: kBorder),
        ),
        textStyle: const TextStyle(color: kText, fontSize: 14),
      ),

      // ── ExpansionTile ─────────────────────────────────────────────────────
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: kMuted,
        collapsedIconColor: kMuted,
        textColor: kText,
        collapsedTextColor: kText,
      ),
    );
  }
}
