import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// HavenKeep Design System
///
/// Palette is fixed — indigo / violet on near-black, with a gold accent.
/// The "premium" feel comes from depth (a layered surface ladder + ambient
/// shadows + hairline highlights), tight typography, and consistent motion —
/// not from new colors.

// ============================================
// COLORS
// ============================================

class HavenColors {
  HavenColors._();

  // ---- Surface ladder -------------------------------------------------
  // Four tiers, each a few percent lighter than the last, so stacked cards
  // read as physically layered rather than flat. `canvas` is the page
  // background; `surface` is a resting card; `surfaceElevated` is a card
  // that sits on top of another surface; `surfaceHigh` is sheets / dialogs
  // / popovers that float above everything.
  static const Color canvas = Color(0xFF080B14);
  static const Color background = canvas; // legacy alias — same value
  static const Color surface = Color(0xFF111626);
  static const Color surfaceElevated = Color(0xFF181E32);
  static const Color surfaceHigh = Color(0xFF20273E);
  // Legacy alias kept so existing call sites compile; maps to the new
  // "elevated" tier.
  static const Color elevated = surfaceHigh;

  // ---- Accents — indigo / violet, aligned with the marketing site. ----
  static const Color primary = Color(0xFF6366F1);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color accent = Color(0xFF818CF8);
  static const Color accentSecondary = Color(0xFFA78BFA);
  static const Color gold = Color(0xFFFFD700);

  // ---- Status --------------------------------------------------------
  static const Color active = Color(0xFF10B981);
  static const Color success = active;
  static const Color expiring = Color(0xFFF59E0B);
  static const Color expired = Color(0xFFEF4444);

  // ---- Text ----------------------------------------------------------
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textTertiary = Color(0xFF7C8BA4);

  // ---- Borders -------------------------------------------------------
  // `border` — visible card outline. `borderHairline` — inner dividers /
  // table rules, barely there. `topHighlight` — the 1px lighter line along
  // a card's top edge that sells "light source from above" depth.
  static const Color border = Color(0xFF232B40);
  static const Color borderHairline = Color(0x14FFFFFF); // white @ 8%
  static const Color topHighlight = Color(0x1FFFFFFF); // white @ 12%
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

  static final BorderRadius pillRadius = BorderRadius.circular(pill);
  static final BorderRadius cardRadius = BorderRadius.circular(card);
  static final BorderRadius buttonRadius = BorderRadius.circular(button);
  static final BorderRadius inputRadius = BorderRadius.circular(input);
  static final BorderRadius chipRadius = BorderRadius.circular(chip);
}

// ============================================
// ELEVATION
// ============================================

/// Depth tokens. A "level" bundles the surface color, the ambient shadow,
/// and the top-edge highlight border so every elevated thing in the app
/// reads consistently. `HavenCard` is the primary consumer; raw widgets can
/// use these directly when a `HavenCard` doesn't fit.
///
///   * `level0` — flush with the canvas (search fields, list rows on the
///     page background). No shadow, just a hairline outline.
///   * `level1` — a resting card sitting on the canvas. Soft, wide shadow.
///   * `level2` — a card on top of another card, or a hover/pressed lift.
///   * `level3` — sheets, dialogs, menus floating above the page.
class HavenElevation {
  HavenElevation._();

  static const Color _shadow = Color(0xFF000000);

  /// Surface color for a given level.
  static Color surfaceFor(int level) => switch (level) {
        <= 0 => HavenColors.canvas,
        1 => HavenColors.surface,
        2 => HavenColors.surfaceElevated,
        _ => HavenColors.surfaceHigh,
      };

  /// Ambient shadow for a given level. Two stacked shadows — a tight close
  /// one for contact + a wide soft one for the cast — which is what reads
  /// as a real object rather than a flat drop-shadow.
  static List<BoxShadow> shadowFor(int level) => switch (level) {
        <= 0 => const [],
        1 => [
            BoxShadow(
              color: _shadow.withValues(alpha: 0.20),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: _shadow.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        2 => [
            BoxShadow(
              color: _shadow.withValues(alpha: 0.26),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: _shadow.withValues(alpha: 0.16),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        _ => [
            BoxShadow(
              color: _shadow.withValues(alpha: 0.34),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: _shadow.withValues(alpha: 0.22),
              blurRadius: 56,
              offset: const Offset(0, 28),
            ),
          ],
      };

  /// A gradient that fakes a faint light-from-above sheen on a surface.
  /// Layer it over the surface color at low opacity. Used by [HavenCard]'s
  /// elevated/highlight variants.
  static LinearGradient sheen({double strength = 1}) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.05 * strength),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55],
      );

  /// A soft colored glow — a wide, low-alpha blurred shadow in [color].
  /// This is the move that makes one hero element read as "premium" against
  /// a flat dark canvas: a gentle halo, not a hard drop shadow. Use
  /// sparingly — the FAB, the dashboard hero, a featured CTA. `strength`
  /// scales the alpha (1 = default).
  static List<BoxShadow> glow(Color color, {double strength = 1}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.28 * strength),
          blurRadius: 24,
          spreadRadius: -2,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.14 * strength),
          blurRadius: 48,
          spreadRadius: 0,
          offset: const Offset(0, 16),
        ),
      ];
}

// ============================================
// GRADIENTS
// ============================================

/// Named brand gradients so features stop hand-rolling
/// `LinearGradient(colors: [primary, secondary])` everywhere.
class HavenGradients {
  HavenGradients._();

  /// The signature indigo → violet, top-left to bottom-right. Used on the
  /// dashboard hero, premium surfaces, the FAB.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [HavenColors.primary, HavenColors.secondary],
  );

  /// A slightly lighter, airier variant for large surfaces (the hero card)
  /// — accent → accentSecondary so big fills don't go too saturated.
  static const LinearGradient brandSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [HavenColors.accent, HavenColors.accentSecondary],
  );

  /// Vertical brand gradient for tall narrow elements (a left accent
  /// stripe on a card).
  static const LinearGradient brandVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [HavenColors.primary, HavenColors.secondary],
  );
}

// ============================================
// ICON SIZES
// ============================================

class HavenIconSize {
  HavenIconSize._();

  static const double micro = 16;
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
///   * `hero`      — dashboard value card (40/28, bold, tight tracking)
///   * `display`   — screen-level headings (24/20, bold)
///   * `title`     — card titles (16/15, 600)
///   * `body`      — default body (14, 400)
///   * `meta`      — labels and secondary text (12/13, 400/500)
///   * `overline`  — small-caps section labels ("YOUR WARRANTIES")
///   * `badge`     — pill labels (11, 600, letterspaced)
class HavenText {
  HavenText._();

  // Hero / stat — tight negative tracking is what makes big numbers look
  // typeset rather than default.
  static const TextStyle hero = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    color: HavenColors.textPrimary,
    height: 1.05,
    letterSpacing: -1.0,
  );
  static const TextStyle stat = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: HavenColors.textPrimary,
    height: 1.05,
    letterSpacing: -0.6,
  );

  // Display / headline
  static const TextStyle displayLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: HavenColors.textPrimary,
    height: 1.2,
    letterSpacing: -0.5,
  );
  static const TextStyle displayMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: HavenColors.textPrimary,
    height: 1.2,
    letterSpacing: -0.3,
  );

  // Titles
  static const TextStyle titleLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: HavenColors.textPrimary,
    height: 1.3,
    letterSpacing: -0.1,
  );
  static const TextStyle titleMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: HavenColors.textPrimary,
    height: 1.3,
  );

  // Body
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: HavenColors.textPrimary,
    height: 1.45,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: HavenColors.textSecondary,
    height: 1.45,
  );

  // Meta (labels, captions)
  static const TextStyle meta = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: HavenColors.textSecondary,
    height: 1.4,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: HavenColors.textTertiary,
    height: 1.4,
  );

  /// Small-caps section label. Use this for "YOUR WARRANTIES", "NEEDS
  /// ATTENTION", "COMMUNITY SAVINGS" headers — caller passes the text
  /// already upper-cased.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: HavenColors.textTertiary,
    letterSpacing: 1.4,
    height: 1.2,
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
      scaffoldBackgroundColor: HavenColors.canvas,
      // Branded tap feedback: soft indigo glow instead of the default
      // Material gray splash. Applies to every InkWell/Material button.
      splashColor: HavenColors.primary.withValues(alpha: 0.14),
      highlightColor: HavenColors.primary.withValues(alpha: 0.07),
      hoverColor: HavenColors.primary.withValues(alpha: 0.06),
      splashFactory: InkRipple.splashFactory,
      // Keyboard / D-pad focus ring — indigo, never the default teal.
      focusColor: HavenColors.primary.withValues(alpha: 0.4),
      colorScheme: const ColorScheme.dark(
        primary: HavenColors.primary,
        secondary: HavenColors.secondary,
        surface: HavenColors.surface,
        surfaceContainerHighest: HavenColors.surfaceHigh,
        error: HavenColors.expired,
        onPrimary: HavenColors.textPrimary,
        onSecondary: HavenColors.textPrimary,
        onSurface: HavenColors.textPrimary,
        onError: HavenColors.textPrimary,
        outline: HavenColors.border,
        outlineVariant: HavenColors.borderHairline,
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
            letterSpacing: -1.0,
            height: 1.1,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
            letterSpacing: -0.6,
            height: 1.1,
          ),
          headlineLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: HavenColors.textPrimary,
            letterSpacing: -0.3,
            height: 1.2,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: HavenColors.textPrimary,
            letterSpacing: -0.2,
            height: 1.3,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: HavenColors.textPrimary,
            letterSpacing: -0.1,
            height: 1.3,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: HavenColors.textPrimary,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: HavenColors.textSecondary,
            height: 1.45,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: HavenColors.textTertiary,
            height: 1.4,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: HavenColors.textPrimary,
            letterSpacing: 0.1,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: HavenColors.surface,
        elevation: 0,
        // When features opt into elevation, use a soft black ambient shadow
        // (the level-1 token) so depth reads as a real lift, not a gray
        // Material smear.
        shadowColor: const Color(0xFF000000).withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: HavenRadius.cardRadius,
          side: const BorderSide(color: HavenColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        // Elevation is set via .copyWith below (pressed-vs-resting), so we
        // don't pass `elevation:` in styleFrom — it would be dead.
        style: ElevatedButton.styleFrom(
          backgroundColor: HavenColors.primary,
          foregroundColor: HavenColors.textPrimary,
          shadowColor: HavenColors.primary.withValues(alpha: 0.4),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: HavenRadius.buttonRadius,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: HavenSpacing.lg,
            vertical: HavenSpacing.md,
          ),
        ).copyWith(
          // A faint indigo glow under the primary CTA so it lifts off the
          // canvas without a hard shadow.
          elevation: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed) ? 0 : 2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: HavenColors.primary,
          foregroundColor: HavenColors.textPrimary,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: HavenRadius.buttonRadius,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: HavenSpacing.lg,
            vertical: HavenSpacing.md,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HavenColors.textPrimary,
          side: const BorderSide(color: HavenColors.border),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: HavenRadius.buttonRadius,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: HavenSpacing.lg,
            vertical: HavenSpacing.md,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: HavenColors.primary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
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
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: HavenRadius.inputRadius,
          borderSide: const BorderSide(color: HavenColors.expired, width: 2),
        ),
        labelStyle: const TextStyle(color: HavenColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: HavenColors.primary),
        hintStyle: const TextStyle(color: HavenColors.textTertiary),
        prefixIconColor: HavenColors.textTertiary,
        suffixIconColor: HavenColors.textTertiary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HavenSpacing.md,
          vertical: HavenSpacing.sm + 4,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: HavenColors.surface,
        selectedColor: HavenColors.primary,
        side: const BorderSide(color: HavenColors.border),
        labelStyle: HavenText.meta,
        shape: RoundedRectangleBorder(
          borderRadius: HavenRadius.chipRadius,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: HavenColors.borderHairline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: HavenColors.canvas,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: HavenColors.textPrimary,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: HavenColors.textPrimary),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: HavenColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: HavenColors.surfaceHigh,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(HavenRadius.card + 4),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: HavenColors.textTertiary.withValues(alpha: 0.6),
        dragHandleSize: const Size(36, 4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: HavenColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HavenRadius.card),
          side: const BorderSide(color: HavenColors.borderHairline),
        ),
        textStyle: HavenText.body,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor:
              WidgetStatePropertyAll(HavenColors.surfaceHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HavenRadius.card),
              side: const BorderSide(color: HavenColors.borderHairline),
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: HavenColors.surfaceHigh,
        contentTextStyle: HavenText.body,
        actionTextColor: HavenColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HavenRadius.button),
          side: const BorderSide(color: HavenColors.borderHairline),
        ),
        elevation: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: HavenColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HavenRadius.card + 4),
          side: const BorderSide(color: HavenColors.borderHairline),
        ),
        titleTextStyle: HavenText.titleLarge,
        contentTextStyle: HavenText.bodySecondary,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: HavenColors.textSecondary,
        textColor: HavenColors.textPrimary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: HavenColors.surfaceHigh,
          borderRadius: BorderRadius.circular(HavenRadius.pill),
          border: Border.all(color: HavenColors.borderHairline),
        ),
        textStyle: HavenText.caption.copyWith(color: HavenColors.textPrimary),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: HavenColors.primary,
      ),
    );
  }
}
