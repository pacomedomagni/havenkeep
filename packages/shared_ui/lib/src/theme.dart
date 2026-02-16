import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// HavenKeep Design System
///
/// All values from the v6 UX specification.
/// See: docs/havenkeep-ux-spec.md > Brand Identity

// ============================================
// COLORS
// ============================================

class HavenColors {
  HavenColors._();

  // Backgrounds
  static const Color background = Color(0xFF0A0E1A);
  static const Color surface = Color(0xFF141929);
  static const Color elevated = Color(0xFF1C2237);

  // Accents
  static const Color primary = Color(0xFF2563EB);
  static const Color secondary = Color(0xFF60A5FA);
  static const Color accent = Color(0xFF6366F1);
  static const Color accentSecondary = Color(0xFF8B5CF6);
  static const Color gold = Color(0xFFFFD700);

  // Status
  static const Color active = Color(0xFF10B981);
  static const Color success = active;
  static const Color expiring = Color(0xFFF59E0B);
  static const Color expired = Color(0xFFEF4444);

  // Text
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textTertiary = Color(0xFF7C8BA4);

  // Borders
  static const Color border = Color(0xFF1E293B);
}

// ============================================
// SPACING
// ============================================

class HavenSpacing {
  HavenSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// ============================================
// BORDER RADIUS
// ============================================

class HavenRadius {
  HavenRadius._();

  static const double card = 16;
  static const double button = 12;
  static const double input = 10;
  static const double chip = 20;

  static BorderRadius cardRadius = BorderRadius.circular(card);
  static BorderRadius buttonRadius = BorderRadius.circular(button);
  static BorderRadius inputRadius = BorderRadius.circular(input);
  static BorderRadius chipRadius = BorderRadius.circular(chip);
}

// ============================================
// ICON SIZES
// ============================================

class HavenIconSize {
  HavenIconSize._();

  static const double compact = 20;
  static const double standard = 24;
  static const double feature = 32;
}

// ============================================
// THEME
// ============================================

class HavenTheme {
  HavenTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HavenColors.background,
      colorScheme: const ColorScheme.dark(
        primary: HavenColors.primary,
        secondary: HavenColors.secondary,
        surface: HavenColors.surface,
        error: HavenColors.expired,
        onPrimary: HavenColors.textPrimary,
        onSecondary: HavenColors.textPrimary,
        onSurface: HavenColors.textPrimary,
        onError: HavenColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
          ),
          headlineLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: HavenColors.textPrimary,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: HavenColors.textPrimary,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: HavenColors.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: HavenColors.textSecondary,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: HavenColors.textTertiary,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: HavenColors.textPrimary,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: HavenColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: HavenRadius.cardRadius,
          side: const BorderSide(color: HavenColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HavenColors.primary,
          foregroundColor: HavenColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: HavenRadius.buttonRadius,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: HavenSpacing.lg,
            vertical: HavenSpacing.md,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HavenColors.surface,
        border: OutlineInputBorder(
          borderRadius: HavenRadius.inputRadius,
          borderSide: const BorderSide(color: HavenColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: HavenRadius.inputRadius,
          borderSide: const BorderSide(color: HavenColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: HavenRadius.inputRadius,
          borderSide: const BorderSide(color: HavenColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: HavenRadius.inputRadius,
          borderSide: const BorderSide(color: HavenColors.expired),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HavenSpacing.md,
          vertical: HavenSpacing.sm + 4,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: HavenColors.surface,
        selectedItemColor: HavenColors.primary,
        unselectedItemColor: HavenColors.textTertiary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: HavenColors.surface,
        selectedColor: HavenColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: HavenRadius.chipRadius,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: HavenColors.border,
        thickness: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: HavenColors.background,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
