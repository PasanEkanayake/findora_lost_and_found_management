import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Central theme definitions. Screens should always read colors/text styles
/// off `Theme.of(context)` rather than reaching into [AppColors] directly,
/// so dark mode "just works" everywhere except the deliberately-semantic
/// status colors (lost/found/matched), which stay constant in both modes.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      secondary: AppColors.secondary,
      tertiary: AppColors.found,
      error: AppColors.error,
      surface: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      onSurface: isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight,
      onSurfaceVariant:
          isDark ? AppColors.onSurfaceVariantDark : AppColors.onSurfaceVariantLight,
    );

    // Manrope for headings gives the app a bit more personality than the
    // body copy; Inter (via GoogleFonts default text theme) stays highly
    // legible at small sizes for descriptions, timestamps, form labels.
    final baseTextTheme = GoogleFonts.interTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );
    final textTheme = baseTextTheme.copyWith(
      headlineLarge: GoogleFonts.manrope(
        textStyle: baseTextTheme.headlineLarge,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.manrope(
        textStyle: baseTextTheme.headlineMedium,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: GoogleFonts.manrope(
        textStyle: baseTextTheme.headlineSmall,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.manrope(
        textStyle: baseTextTheme.titleLarge,
        fontWeight: FontWeight.w600,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: textTheme.labelLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        height: 64,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
      ),
    );
  }
}
