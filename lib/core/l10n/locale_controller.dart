import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The languages the app is translated into. Add a language by adding its
/// `lib/l10n/app_<code>.arb` file and its entry here (README.md, "Languages").
const List<Locale> kSupportedLocales = [
  Locale('en'),
  Locale('si'),
  Locale('ta'),
];

/// Each language written in itself, so a person can find theirs even when the
/// app is currently in a language they can't read. Deliberately NOT translated.
const Map<String, String> kLanguageSelfNames = {
  'en': 'English',
  'si': 'සිංහල',
  'ta': 'தமிழ்',
};

/// The stored language code -> the locale to use; null (use the phone's
/// language) for no choice or a code the app doesn't have (e.g. a language
/// removed in a later version).
Locale? localeFromCode(String? code) {
  if (code == null) return null;
  for (final locale in kSupportedLocales) {
    if (locale.languageCode == code) return locale;
  }
  return null;
}

/// The locale the app actually shows, given the person's choice ([chosen],
/// null = follow the phone) and the phone's own language list: their choice,
/// else the first phone language we're translated into, else English.
/// Mirrors what Flutter does for the UI, so dates and numbers (formatted by
/// `intl`, which doesn't follow MaterialApp.locale) can agree with it.
Locale resolveLocale(Locale? chosen, List<Locale> deviceLocales) {
  if (chosen != null) return chosen;
  for (final device in deviceLocales) {
    for (final supported in kSupportedLocales) {
      if (supported.languageCode == device.languageCode) return supported;
    }
  }
  return kSupportedLocales.first;
}

/// Makes `DateFormat`/`NumberFormat` (which many screens call without a locale)
/// use [locale], so a Sinhala-language app doesn't show "Oct 18, 2026".
void applyIntlLocale(Locale locale) {
  Intl.defaultLocale = locale.languageCode;
}

/// The person's language choice, remembered across restarts. `null` means
/// "follow the phone's language". Same pattern as [ThemeModeController]:
/// starts as "follow the phone", then updates once the stored value is read.
class LocaleController extends Notifier<Locale?> {
  static const _prefsKey = 'findora.locale';

  @override
  Locale? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = localeFromCode(prefs.getString(_prefsKey));
    if (stored != state) state = stored;
  }

  /// [locale] null = follow the phone.
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, locale.languageCode);
    }
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale?>(LocaleController.new);
