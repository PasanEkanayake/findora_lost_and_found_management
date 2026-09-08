import 'package:flutter/material.dart';

/// The app's brand palette, kept separate from [AppTheme] so designers/devs
/// can tweak the actual colors without touching theme wiring.
///
/// Design intent: a deep teal reads as trustworthy and calm (this is a
/// "please help me get my things back" app, not a flashy consumer one),
/// while status colors on item cards (lost / found / matched) carry real
/// meaning rather than being decorative.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF0F6E56); // deep teal
  static const Color primaryLight = Color(0xFF3FA98A);
  static const Color secondary = Color(0xFFE8A33D); // warm amber

  // Status — used for item badges, not just theme accents
  static const Color lost = Color(0xFFD8543C); // coral-red, urgency
  static const Color found = Color(0xFF2F8F5B); // green, positive
  static const Color matched = Color(0xFFE8A33D); // amber, needs attention
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
