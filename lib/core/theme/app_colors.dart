import 'package:flutter/material.dart';

/// The app's brand palette, kept separate from [AppTheme] so designers/devs
/// can tweak the actual colors without touching theme wiring.
///
/// Matches the Findora logo (assets/images/logo.png): a vivid blue
/// magnifying glass with a cyan lens and a warm orange/amber location pin.
/// Status colors on item cards (lost / found / matched) stay semantic
/// rather than decorative, independent of the brand colors.
class AppColors {
  AppColors._();

  // Brand — sourced from the logo itself, not picked independently
  static const Color primary = Color(0xFF1565D8); // logo's magnifying-glass blue
  static const Color primaryLight = Color(0xFF29B6F6); // logo's lens cyan
  static const Color secondary = Color(0xFFF5A623); // logo's pin orange

  // Status — used for item badges, not just theme accents
  static const Color lost = Color(0xFFD8543C); // coral-red, urgency
  static const Color found = Color(0xFF2F8F5B); // green, positive
  static const Color matched = Color(0xFFF5A623); // amber, needs attention
  static const Color resolved = Color(0xFF6B7280); // muted gray

  // Light surfaces
  static const Color backgroundLight = Color(0xFFFAFAF8);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color onSurfaceLight = Color(0xFF1C1C1E);
  static const Color onSurfaceVariantLight = Color(0xFF6B7280);

  // Dark surfaces
  static const Color backgroundDark = Color(0xFF121412);
  static const Color surfaceDark = Color(0xFF1E211F);
  static const Color onSurfaceDark = Color(0xFFECEDEB);
  static const Color onSurfaceVariantDark = Color(0xFFA3A9A5);

  static const Color error = Color(0xFFBA1A1A);
}
