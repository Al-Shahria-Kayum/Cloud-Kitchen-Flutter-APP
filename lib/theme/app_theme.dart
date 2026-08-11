import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ---------------------------------------------------------------------------
/// Cloud Kitchen design system.
///
/// Single source of truth for color, type, spacing, radius and motion across
/// every screen. Screens should reach for these tokens (and the shared
/// widgets in lib/widgets/) rather than hard-coding colors or paddings.
/// ---------------------------------------------------------------------------

/// 4pt spacing scale.
class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double xxxl = 40;
}

/// Corner radii. Kept to four deliberate steps rather than ad-hoc values.
class AppRadius {
  const AppRadius._();
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double pill = 999;

  static BorderRadius get smBr => BorderRadius.circular(sm);
  static BorderRadius get mdBr => BorderRadius.circular(md);
  static BorderRadius get lgBr => BorderRadius.circular(lg);
  static BorderRadius get pillBr => BorderRadius.circular(pill);
}

/// Motion durations + the one curve used for anything eased.
class AppMotion {
  const AppMotion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
  static const Curve curve = Curves.easeOutCubic;
}

/// Semantic colors that sit outside Material's ColorScheme (success, warning,
/// rating stars, map pins, shimmer). Access via `Theme.of(context).extension<AppColors>()`.
class AppColors extends ThemeExtension<AppColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color ratingStar;
  final Color mapKitchen;
  final Color mapCustomer;
  final Color mapRider;
  final Color shimmerBase;
  final Color shimmerHighlight;

  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.ratingStar,
    required this.mapKitchen,
    required this.mapCustomer,
    required this.mapRider,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });

  static const light = AppColors(
    success: Color(0xFF3F7D58),
    onSuccess: Colors.white,
    successContainer: Color(0xFFDDEFE2),
    onSuccessContainer: Color(0xFF1D4429),
    warning: Color(0xFFB9791E),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFBEACB),
    onWarningContainer: Color(0xFF5C3E0B),
    ratingStar: Color(0xFFE8A93B),
    mapKitchen: Color(0xFFD64545),
    mapCustomer: Color(0xFF2F6FBA),
    mapRider: Color(0xFF3F7D58),
    shimmerBase: Color(0xFFEFE8DF),
    shimmerHighlight: Color(0xFFFAF6F0),
  );

  static const dark = AppColors(
    success: Color(0xFF6FCF8C),
    onSuccess: Color(0xFF073318),
    successContainer: Color(0xFF1D3A28),
    onSuccessContainer: Color(0xFFC7EFD3),
    warning: Color(0xFFE3A94D),
    onWarning: Color(0xFF3D2700),
    warningContainer: Color(0xFF4A3714),
    onWarningContainer: Color(0xFFFBE1B3),
    ratingStar: Color(0xFFF2BB5C),
    mapKitchen: Color(0xFFFF6B5E),
    mapCustomer: Color(0xFF6FA8DC),
    mapRider: Color(0xFF6FCF8C),
    shimmerBase: Color(0xFF262220),
    shimmerHighlight: Color(0xFF322D29),
  );

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? ratingStar,
    Color? mapKitchen,
    Color? mapCustomer,
    Color? mapRider,
    Color? shimmerBase,
    Color? shimmerHighlight,
  }) {
    return AppColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      ratingStar: ratingStar ?? this.ratingStar,
      mapKitchen: mapKitchen ?? this.mapKitchen,
      mapCustomer: mapCustomer ?? this.mapCustomer,
      mapRider: mapRider ?? this.mapRider,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      ratingStar: Color.lerp(ratingStar, other.ratingStar, t)!,
      mapKitchen: Color.lerp(mapKitchen, other.mapKitchen, t)!,
      mapCustomer: Color.lerp(mapCustomer, other.mapCustomer, t)!,
      mapRider: Color.lerp(mapRider, other.mapRider, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

/// The kitchen brand gradient (used sparingly — role headers only, not every card).
const List<Color> kBrandGradient = [Color(0xFF1B2A2F), Color(0xFF0D1517)];

class AppTheme {
  const AppTheme._();

  static const _lightPrimary = Color(0xFFE85D2C);
  static const _lightOnPrimary = Colors.white;
  static const _lightPrimaryContainer = Color(0xFFFFE0CC);
  static const _lightOnPrimaryContainer = Color(0xFF7A2B00);
  static const _lightSecondary = Color(0xFF1B2A2F);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightOnSurface = Color(0xFF241E19);
  static const _lightBackground = Color(0xFFFBF7F2);
  static const _lightOutline = Color(0xFFE7DFD3);
  static const _lightError = Color(0xFFC1401F);

  static const _darkPrimary = Color(0xFFFF9752);
  static const _darkOnPrimary = Color(0xFF3D1600);
  static const _darkPrimaryContainer = Color(0xFF5C2200);
  static const _darkOnPrimaryContainer = Color(0xFFFFD9BA);
  static const _darkSecondary = Color(0xFFB7C6CB);
  static const _darkSurface = Color(0xFF1E2225);
  static const _darkOnSurface = Color(0xFFF1ECE6);
  static const _darkBackground = Color(0xFF15181A);
  static const _darkOutline = Color(0xFF3A3532);
  static const _darkError = Color(0xFFFF6B5E);

  static TextTheme _textTheme(Color ink, Color inkSoft) {
    final base = TextTheme(
      displayLarge: GoogleFonts.fraunces(fontSize: 34, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.4, color: ink),
      displayMedium: GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w700, height: 1.18, letterSpacing: -0.3, color: ink),
      displaySmall: GoogleFonts.fraunces(fontSize: 23, fontWeight: FontWeight.w600, height: 1.2, color: ink),
      headlineMedium: GoogleFonts.fraunces(fontSize: 20, fontWeight: FontWeight.w600, height: 1.25, color: ink),
      headlineSmall: GoogleFonts.fraunces(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3, color: ink),
      titleLarge: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: ink),
      titleMedium: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
      titleSmall: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
      bodyLarge: GoogleFonts.manrope(fontSize: 15.5, fontWeight: FontWeight.w500, height: 1.5, color: ink),
      bodyMedium: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w500, height: 1.45, color: inkSoft),
      bodySmall: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4, color: inkSoft),
      labelLarge: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.1, color: ink),
      labelMedium: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: inkSoft),
      labelSmall: GoogleFonts.manrope(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: inkSoft),
    );
    return base;
  }

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: _lightPrimary,
      onPrimary: _lightOnPrimary,
      primaryContainer: _lightPrimaryContainer,
      onPrimaryContainer: _lightOnPrimaryContainer,
      secondary: _lightSecondary,
      onSecondary: Colors.white,
      surface: _lightSurface,
      onSurface: _lightOnSurface,
      error: _lightError,
      onError: Colors.white,
      outline: _lightOutline,
      surfaceTint: Colors.transparent,
    );
    return _build(scheme, _lightBackground, _lightOnSurface, const Color(0xFF6E645B), AppColors.light);
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: _darkPrimary,
      onPrimary: _darkOnPrimary,
      primaryContainer: _darkPrimaryContainer,
      onPrimaryContainer: _darkOnPrimaryContainer,
      secondary: _darkSecondary,
      onSecondary: Color(0xFF16232A),
      surface: _darkSurface,
      onSurface: _darkOnSurface,
      error: _darkError,
      onError: Color(0xFF3D0F0A),
      outline: _darkOutline,
      surfaceTint: Colors.transparent,
    );
    return _build(scheme, _darkBackground, _darkOnSurface, const Color(0xFFAFA79E), AppColors.dark);
  }

  static ThemeData _build(ColorScheme scheme, Color background, Color ink, Color inkSoft, AppColors extra) {
    final textTheme = _textTheme(ink, inkSoft);
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: [extra],

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: ink,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: IconThemeData(color: ink),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgBr,
          side: BorderSide(color: scheme.outline.withValues(alpha: isDark ? 0.5 : 0.7), width: 1),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
        hintStyle: textTheme.bodyMedium,
        labelStyle: textTheme.bodyMedium,
        border: OutlineInputBorder(borderRadius: AppRadius.mdBr, borderSide: BorderSide(color: scheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.mdBr, borderSide: BorderSide(color: scheme.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.mdBr, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: AppRadius.mdBr, borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: AppRadius.mdBr, borderSide: BorderSide(color: scheme.error, width: 1.6)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2, horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBr),
          elevation: 0,
          textStyle: textTheme.labelLarge?.copyWith(color: scheme.onPrimary),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBr),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge?.copyWith(color: scheme.primary),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smBr),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : scheme.surface,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.outline.withValues(alpha: 0.3),
        labelStyle: textTheme.labelMedium?.copyWith(color: ink),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.pillBr),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      ),

      dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1, space: AppSpacing.xxl),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: inkSoft,
        showUnselectedLabels: true,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: background),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBr),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgBr),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: ink),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
        elevation: 0,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.primary.withValues(alpha: 0.35) : null),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBr),
      ),
    );
  }
}
