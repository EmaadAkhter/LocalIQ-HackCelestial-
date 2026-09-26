import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// LocalIQ · WARM EDITORIAL CRAFT design system
//
// Palette: warm ivory canvas, terracotta primary, sand surfaces, deep ochre text.
// NO blue, no purple, no cyan, no neon, no cold electric gradients.
// =============================================================================

abstract final class AppColors {
  // ── Primary ────────────────────────────────────────────────────────────────
  static const primary = Color(0xFFFF5A36);
  static const primaryDark = Color(0xFFE65100);
  static const primarySurface = Color(0xFFFFF0EB);

  // ── Canvas / surfaces ─────────────────────────────────────────────────────
  static const canvas = Color(0xFFFCFAF5);
  static const surfaceLifted = Color(0xFFFFFDF9);
  static const surfaceSecondary = Color(0xFFF5EFE6);
  static const surfaceDeep = Color(0xFFEFE8DC);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const text = Color(0xFF2E2724);
  static const textMuted = Color(0xFF5B403A);
  static const textFaint = Color(0xFF8C7269);

  // ── Borders ───────────────────────────────────────────────────────────────
  static const border = Color(0xFFE7DFD3);
  static const borderStrong = Color(0xFFD4C5B5);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const success = Color(0xFF15803D);
  static const successSurface = Color(0xFFECFDF5);
  static const warning = Color(0xFFB45309);
  static const warningSurface = Color(0xFFFEF3C7);
  static const danger = Color(0xFFDC2626);
  static const dangerSurface = Color(0xFFFEF2F2);

  // ── Accents ───────────────────────────────────────────────────────────────
  /// Warm amber — used for stars, ratings, highlights.
  static const star = Color(0xFFD97706);
  /// Warm green for "open now" and "great right now".
  static const openGreen = Color(0xFF16A34A);

  // ── Bottom nav ────────────────────────────────────────────────────────────
  static const navBar = Color(0xFFFFFDF9);
  static const navBarDivider = Color(0xFFEFE8DC);
  static const navActive = Color(0xFFFF5A36);
  static const navInactive = Color(0xFF736B66);

  // ── Gradients ─────────────────────────────────────────────────────────────
  /// Warm terracotta hero gradient — for primary action surfaces only.
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF5A36), Color(0xFFE65100)],
  );

  /// Warm sand gradient — for editorial card backgrounds.
  static const sandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5EFE6), Color(0xFFEFE8DC)],
  );

  // ── Backward-compatible aliases (old cold-palette names → warm equivalents) ──
  // These exist so the full codebase still compiles during incremental migration.
  static const navy = Color(0xFF2E2724);
  static const navySoft = Color(0xFF5B403A);
  static const blue = Color(0xFFFF5A36);
  static const violet = Color(0xFFE65100);
  static const sky = Color(0xFFFFF0EB);
  static const lavender = Color(0xFFF5EFE6);
  static const surface = Color(0xFFFFFDF9);
  static const surfaceMuted = Color(0xFFF5EFE6);
  static const textSecondary = Color(0xFF5B403A);
  static const brandWash = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5EFE6), Color(0xFFEFE8DC)],
  );
  static const background = canvas; // legacy alias
}


// =============================================================================
// Radius
// =============================================================================

abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

// =============================================================================
// Spacing — 8pt rhythm
// =============================================================================

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double outerMargin = 20;
}

// =============================================================================
// Breakpoints
// =============================================================================

abstract final class Breakpoints {
  static const double mobile = 760;
  static const double compact = 1024;
  static const double wide = 1280;
  static const double maxContent = 1400;
  static const double sidebar = 348;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < compact;
  static bool isDesktop(double width) => width >= compact;
  static bool isWide(double width) => width >= wide;

  static int recoColumns(double width) => switch (width) {
        < 620 => 1,
        < 1180 => 2,
        _ => 2,
      };

  static double gutter(double width) => width < 560 ? 20 : 24;
}

// =============================================================================
// Shadows — warm tonal, no blue-grey
// =============================================================================

abstract final class AppShadows {
  static List<BoxShadow> get card => [
        BoxShadow(
          color: AppColors.text.withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: AppColors.text.withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get raised => [
        BoxShadow(
          color: AppColors.primaryDark.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get sheet => [
        BoxShadow(
          color: AppColors.text.withValues(alpha: 0.08),
          blurRadius: 32,
          offset: const Offset(0, -4),
        ),
      ];
}

// =============================================================================
// Motion
// =============================================================================

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const curve = Curves.easeOutCubic;

  /// Legacy alias kept for compatibility with existing usages.
  static const base = medium;
}

// =============================================================================
// Theme
// =============================================================================

abstract final class AppTheme {
  static ThemeData light() {
    // ── Typography ───────────────────────────────────────────────────────────
    // Manrope → headings, titles, major display.
    // DM Sans  → body, labels, controls, chips, buttons.
    // (Newsreader Italic loaded inline where needed for editorial copy.)

    final dmBase = GoogleFonts.dmSansTextTheme();
    final text = dmBase.copyWith(
      displayLarge: GoogleFonts.manrope(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: AppColors.text,
        height: 1.05,
        fontSize: 57,
      ),
      displayMedium: GoogleFonts.manrope(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: AppColors.text,
        height: 1.08,
        fontSize: 45,
      ),
      displaySmall: GoogleFonts.manrope(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: AppColors.text,
        height: 1.1,
        fontSize: 36,
      ),
      headlineLarge: GoogleFonts.manrope(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        color: AppColors.text,
        height: 1.15,
        fontSize: 32,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: AppColors.text,
        height: 1.18,
        fontSize: 28,
      ),
      headlineSmall: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.text,
        height: 1.2,
        fontSize: 24,
      ),
      titleLarge: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: AppColors.text,
        fontSize: 20,
      ),
      titleMedium: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        fontSize: 16,
      ),
      titleSmall: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        fontSize: 14,
      ),
      bodyLarge: GoogleFonts.dmSans(
        color: AppColors.text,
        height: 1.55,
        fontSize: 16,
      ),
      bodyMedium: GoogleFonts.dmSans(
        color: AppColors.textMuted,
        height: 1.5,
        fontSize: 14,
      ),
      bodySmall: GoogleFonts.dmSans(
        color: AppColors.textFaint,
        height: 1.4,
        fontSize: 12,
      ),
      labelLarge: GoogleFonts.dmSans(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: AppColors.text,
      ),
      labelMedium: GoogleFonts.dmSans(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: AppColors.textMuted,
      ),
      labelSmall: GoogleFonts.dmSans(
        fontWeight: FontWeight.w600,
        fontSize: 11,
        color: AppColors.textFaint,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primarySurface,
        onPrimaryContainer: AppColors.primaryDark,
        secondary: AppColors.primaryDark,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.surfaceSecondary,
        onSecondaryContainer: AppColors.text,
        surface: AppColors.surfaceLifted,
        onSurface: AppColors.text,
        surfaceContainerHighest: AppColors.surfaceSecondary,
        outline: AppColors.border,
        outlineVariant: AppColors.border,
        error: AppColors.danger,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.canvas,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      splashColor: AppColors.primary.withValues(alpha: 0.06),
      highlightColor: AppColors.primary.withValues(alpha: 0.04),

      // ── AppBar ─────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceLifted,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.manrope(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.text, size: 22),
        actionsIconTheme: const IconThemeData(color: AppColors.textMuted, size: 22),
      ),

      // ── Card ───────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.surfaceLifted,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      // ── Divider ────────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      dividerColor: AppColors.border,

      // ── Icons ──────────────────────────────────────────────────────────────
      iconTheme: const IconThemeData(color: AppColors.textMuted, size: 20),

      // ── FilledButton ───────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),

      // ── OutlinedButton ─────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          backgroundColor: AppColors.surfaceLifted,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),

      // ── TextButton ─────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, 40),
          textStyle: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),

      // ── Chip ───────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceSecondary,
        selectedColor: AppColors.primarySurface,
        side: const BorderSide(color: AppColors.border),
        labelStyle: GoogleFonts.dmSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      // ── Input ──────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSecondary,
        isDense: true,
        hintStyle: GoogleFonts.dmSans(
          color: AppColors.textFaint,
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.dmSans(
          color: AppColors.textMuted,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: GoogleFonts.dmSans(
          color: AppColors.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: _inputBorder(AppColors.border),
        enabledBorder: _inputBorder(AppColors.border),
        focusedBorder: _inputBorder(AppColors.primary, width: 1.5),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.5),
      ),

      // ── Slider ─────────────────────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.border,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.10),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),

      // ── SnackBar ───────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.text,
        contentTextStyle: GoogleFonts.dmSans(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      ),

      // ── BottomSheet ────────────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceLifted,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        showDragHandle: true,
        dragHandleColor: AppColors.border,
        dragHandleSize: Size(36, 4),
      ),

      // ── Dialog ─────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceLifted,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),

      // ── BottomNavigationBar ────────────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.navBar,
        selectedItemColor: AppColors.navActive,
        unselectedItemColor: AppColors.navInactive,
        selectedLabelStyle: GoogleFonts.dmSans(
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
        unselectedLabelStyle: GoogleFonts.dmSans(
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // ── NavigationBar ──────────────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.navBar,
        indicatorColor: AppColors.primarySurface,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.navActive, size: 22);
          }
          return const IconThemeData(color: AppColors.navInactive, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.dmSans(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              color: AppColors.navActive,
            );
          }
          return GoogleFonts.dmSans(
            fontWeight: FontWeight.w600,
            fontSize: 10,
            color: AppColors.navInactive,
          );
        }),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 64,
      ),

      // ── Transitions ────────────────────────────────────────────────────────
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

// =============================================================================
// Typography helpers — for inline Newsreader italic editorial copy
// =============================================================================

abstract final class AppTypography {
  /// Newsreader italic — for editorial/reflective copy only.
  static TextStyle newsreaderItalic({
    double fontSize = 16,
    Color color = AppColors.textMuted,
    double height = 1.5,
  }) =>
      GoogleFonts.newsreader(
        fontSize: fontSize,
        fontStyle: FontStyle.italic,
        color: color,
        height: height,
        fontWeight: FontWeight.w400,
      );

  /// Manrope heading.
  static TextStyle manrope({
    double fontSize = 20,
    FontWeight fontWeight = FontWeight.w700,
    Color color = AppColors.text,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.manrope(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// DM Sans body/label.
  static TextStyle dmSans({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.textMuted,
    double? height,
  }) =>
      GoogleFonts.dmSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );
}

