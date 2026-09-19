import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the person's manual light/dark/system choice across app
/// restarts — `shared_preferences` is already a dependency (used for the
/// onboarding-seen flag), so no new package is needed.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _prefsKey = 'findora.theme_mode';

  @override
  ThemeMode build() {
    // Starts as system while the async read below resolves, then updates
    // once the stored value (if any) comes back — same "reasonable default
    // now, correct value shortly after" tradeoff OnboardingPrefs makes.
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => ThemeMode.system,
    );
    if (mode != state) state = mode;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
