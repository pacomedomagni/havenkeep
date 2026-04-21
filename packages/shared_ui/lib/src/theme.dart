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

  // Accents — aligned with marketing site (indigo / violet).
  static const Color primary = Color(0xFF6366F1);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color accent = Color(0xFF818CF8);
  static const Color accentSecondary = Color(0xFFA78BFA);
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

  static const double pill = 8;
  static const double input = 10;
  static const double button = 12;
  static const double card = 16;
  static const double chip = 20;
  static const double micro = 4;

  static BorderRadius pillRadius = BorderRadius.circular(pill);
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
// TYPOGRAPHY (named roles)
// ============================================

/// Named roles so features never hand-roll `TextStyle(fontSize: 13, ...)`.
/// Sizes mirror the type scale in [HavenTheme.dark]'s `textTheme`, so using
/// these is equivalent to `Theme.of(context).textTheme.*` without the
/// `MediaQuery` lookup.
///
/// Rules of thumb:
///   * `hero`     — dashboard value card (40/28, bold)
///   * `display`  — screen-level headings (24/20, bold)
///   * `title`    — card titles (16/15, 600)
///   * `body`     — default body (14, 400)
///   * `meta`     — labels and secondary text (12/13, 400/500)
///   * `micro`    — badges, pill labels (11, 600, letterspaced)
class HavenText {
  HavenText._();

  // Hero / stat
  static const TextStyle hero = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    color: HavenColors.textPrimary,
    height: 1.1,
  );
  static const TextStyle stat = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: HavenColors.textPrimary,
    height: 1.1,
  );

  // Display / headline
  static const TextStyle displayLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: HavenColors.textPrimary,
  );
  static const TextStyle displayMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: HavenColors.textPrimary,
  );

  // Titles
  static const TextStyle titleLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: HavenColors.textPrimary,
  );
  static const TextStyle titleMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: HavenColors.textPrimary,
  );

  // Body
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: HavenColors.textPrimary,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: HavenColors.textSecondary,
  );

  // Meta (labels, captions)
  static const TextStyle meta = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: HavenColors.textSecondary,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: HavenColors.textTertiary,
  );

  // Micro (badge labels, small pills)
  static const TextStyle badge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: HavenColors.textSecondary,
    letterSpacing: 0.8,
  );
}

// ============================================
// MOTION
// ============================================

/// Shared durations and curves so features never hand-roll their own timing.
class HavenMotion {
  HavenMotion._();

  /// Fast feedback — chip taps, micro state flips.
  static const Duration fast = Duration(milliseconds: 180);

  /// Default ease — most UI transitions.
  static const Duration medium = Duration(milliseconds: 240);

  /// Longer transitions — page moves, accordion expands.
  static const Duration slow = Duration(milliseconds: 320);

  /// Celebratory springs.
  static const Duration celebration = Duration(milliseconds: 640);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve spring = Curves.elasticOut;
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
      // Branded tap feedback: soft indigo glow instead of the default
      // Material gray splash. Applies to every InkWell/Material button.
      splashColor: HavenColors.primary.withValues(alpha: 0.12),
      highlightColor: HavenColors.primary.withValues(alpha: 0.06),
      hoverColor: HavenColors.primary.withValues(alpha: 0.06),
      splashFactory: InkRipple.splashFactory,
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
        // When features opt into elevation, use a subtle indigo-tinted
        // shadow so depth reads as brand, not default Material gray.
        shadowColor: HavenColors.primary.withValues(alpha: 0.35),
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
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: HavenColors.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(HavenRadius.card),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: HavenColors.textTertiary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: HavenColors.elevated,
        contentTextStyle: HavenText.body,
        actionTextColor: HavenColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HavenRadius.button),
        ),
        elevation: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: HavenColors.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HavenRadius.card),
        ),
        titleTextStyle: HavenText.titleLarge,
        contentTextStyle: HavenText.bodySecondary,
      ),
    );
  }
}
