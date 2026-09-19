import 'package:shared_preferences/shared_preferences.dart';

/// Whether the onboarding carousel has already been shown, persisted
/// locally (not per-account — onboarding explains the app, not the
/// user's data, so it only needs to run once per device). Uses the
/// modern SharedPreferencesAsync API rather than the legacy singleton,
/// per the package's own current guidance.
class OnboardingPrefs {
  OnboardingPrefs._();

  static const _hasSeenKey = 'has_seen_onboarding';
  static final _prefs = SharedPreferencesAsync();

  static Future<bool> hasSeenOnboarding() async {
    return await _prefs.getBool(_hasSeenKey) ?? false;
  }

  static Future<void> markOnboardingSeen() async {
    await _prefs.setBool(_hasSeenKey, true);
  }
}
