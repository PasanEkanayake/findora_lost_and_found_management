import 'dart:convert';
import 'dart:io';

import 'package:findora/core/l10n/locale_controller.dart';
import 'package:findora/features/matches/matches_screen.dart';
import 'package:findora/features/profile/profile_screen.dart';
import 'package:findora/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_matches_repository.dart';
import 'support/flows.dart';
import 'support/test_app.dart';

Map<String, dynamic> _arb(String code) =>
    jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync()) as Map<String, dynamic>;

Set<String> _keys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// The {placeholder} names a message uses, e.g. {count} in a plural.
Set<String> _placeholders(String message) =>
    RegExp(r'\{(\w+)\s*[,}]').allMatches(message).map((m) => m.group(1)!).toSet();

void main() {
  final english = _arb('en');
  final otherLanguages = {'si': _arb('si'), 'ta': _arb('ta')};

  group('translation files', () {
    for (final entry in otherLanguages.entries) {
      final code = entry.key;
      final arb = entry.value;

      test('$code: has exactly the keys English has (nothing missing, nothing stale)', () {
        final missing = _keys(english).difference(_keys(arb));
        final extra = _keys(arb).difference(_keys(english));
        expect(missing, isEmpty, reason: 'untranslated in $code');
        expect(extra, isEmpty, reason: 'in $code but not in English');
      });

      test('$code: declares its own locale and has no empty strings', () {
        expect(arb['@@locale'], code);
        for (final key in _keys(arb)) {
          expect((arb[key] as String).trim(), isNotEmpty, reason: '$code.$key');
        }
      });

      test('$code: uses the same {placeholders} as English in every message', () {
        for (final key in _keys(english)) {
          expect(
            _placeholders(arb[key] as String),
            _placeholders(english[key] as String),
            reason: '$code.$key',
          );
        }
      });

      test('$code: filter chips keep their emoji', () {
        for (final key in _keys(english).where((k) => k.startsWith('matchFilter'))) {
          final englishEmoji = (english[key] as String).runes.first;
          if (englishEmoji > 0x2000) {
            expect((arb[key] as String).runes.first, englishEmoji, reason: '$code.$key');
          }
        }
      });

      test('$code: is not just a copy of the English text', () {
        final untranslated = _keys(english)
            .where((k) => arb[k] == english[k] && (english[k] as String).length > 12)
            .toList();
        expect(untranslated, isEmpty, reason: '$code still has English for $untranslated');
      });
    }

    test('English: every message has a description for the translators', () {
      for (final key in _keys(english)) {
        expect(english['@$key'], isA<Map>(), reason: key);
        expect((english['@$key'] as Map)['description'], isNotEmpty, reason: key);
      }
    });

    test('English: a literal apostrophe is written as two (ICU quoting)', () {
      for (final key in _keys(english)) {
        final message = english[key] as String;
        final lone = RegExp(r"(?<!')'(?!')").hasMatch(message);
        expect(lone, isFalse, reason: '$key has a single apostrophe — write \'\'');
      }
    });
  });

  group('generated localizations', () {
    test('the app is offered in English, Sinhala and Tamil', () {
      expect(AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
          {'en', 'si', 'ta'});
      expect(kSupportedLocales.map((l) => l.languageCode).toSet(), {'en', 'si', 'ta'});
      expect(kLanguageSelfNames.keys.toSet(), {'en', 'si', 'ta'});
    });

    test('each language reads its own text', () {
      expect(lookupAppLocalizations(const Locale('en')).matchesSectionNeedsInput, 'Needs your input');
      expect(lookupAppLocalizations(const Locale('si')).matchesSectionNeedsInput, 'ඔබේ තීරණය අවශ්‍යයි');
      expect(lookupAppLocalizations(const Locale('ta')).matchesSectionNeedsInput, 'உங்கள் முடிவு தேவை');
    });

    test('a doubled apostrophe in the file shows as one', () {
      expect(lookupAppLocalizations(const Locale('en')).offlineBanner,
          "You're offline — showing what's already loaded");
    });

    test('plurals: "within a day" for 0 and 1, "in N days" otherwise, in every language', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.expiryExpiringDays(1), contains('within a day'));
      expect(en.expiryExpiringDays(0), contains('within a day'));
      expect(en.expiryExpiringDays(5), contains('in 5 days'));
      for (final code in ['si', 'ta']) {
        final l10n = lookupAppLocalizations(Locale(code));
        expect(l10n.expiryExpiringDays(5), contains('5'), reason: code);
        expect(l10n.expiryExpiringDays(5), isNot(equals(l10n.expiryExpiringDays(1))), reason: code);
      }
    });
  });

  group('locale helpers', () {
    test('localeFromCode: known codes, and null for none or unknown', () {
      expect(localeFromCode('si'), const Locale('si'));
      expect(localeFromCode('ta'), const Locale('ta'));
      expect(localeFromCode(null), isNull);
      expect(localeFromCode('fr'), isNull);
    });

    test('resolveLocale: the choice wins, else the first phone language we have, else English', () {
      expect(resolveLocale(const Locale('ta'), const [Locale('si')]), const Locale('ta'));
      expect(resolveLocale(null, const [Locale('fr'), Locale('si', 'LK')]), const Locale('si'));
      expect(resolveLocale(null, const [Locale('fr'), Locale('de')]), const Locale('en'));
      expect(resolveLocale(null, const []), const Locale('en'));
    });
  });

  group('LocaleController', () {
    test('remembers the choice across restarts, and "follow the phone" clears it', () async {
      SharedPreferences.setMockInitialValues({});

      final first = ProviderContainer();
      addTearDown(first.dispose);
      await first.read(localeProvider.notifier).setLocale(const Locale('si'));
      expect(first.read(localeProvider), const Locale('si'));

      // A fresh start reads it back.
      final second = ProviderContainer();
      addTearDown(second.dispose);
      second.read(localeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(second.read(localeProvider), const Locale('si'));

      await second.read(localeProvider.notifier).setLocale(null);
      final third = ProviderContainer();
      addTearDown(third.dispose);
      third.read(localeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(third.read(localeProvider), isNull);
    });

    test('a stored code the app no longer has falls back to following the phone', () async {
      SharedPreferences.setMockInitialValues({'findora.locale': 'xx'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(localeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(localeProvider), isNull);
    });
  });

  group('screens in other languages', () {
    for (final entry in {
      'si': ('ඔබේ තීරණය අවශ්‍යයි', 'මෙයයි!', 'ගැළපෙන්නේ නැත'),
      'ta': ('உங்கள் முடிவு தேவை', 'இதுதான்!', 'பொருத்தமில்லை'),
    }.entries) {
      testWidgets('${entry.key}: the Matches tab shows translated headings and buttons',
          (tester) async {
        final repo = FakeMatchesRepository([FakeMatch(id: 'm1', title: 'Found brown wallet')]);
        await pumpApp(
          tester,
          const MatchesScreen(),
          overrides: matchesOverrides(repo),
          locale: Locale(entry.key),
        );

        final (heading, confirm, dismiss) = entry.value;
        expect(find.text(heading), findsOneWidget);
        expect(find.text(confirm), findsOneWidget);
        expect(find.text(dismiss), findsOneWidget);
        expect(find.text('Needs your input'), findsNothing);
      });
    }

    testWidgets('si: confirming shows the translated "waiting" note and section', (tester) async {
      final repo = FakeMatchesRepository([FakeMatch(id: 'm1', title: 'Found brown wallet')]);
      await pumpApp(
        tester,
        const MatchesScreen(),
        overrides: matchesOverrides(repo),
        locale: const Locale('si'),
      );

      await tapText(tester, 'මෙයයි!');
      final si = lookupAppLocalizations(const Locale('si'));
      expect(find.text(si.matchesSectionWaiting), findsOneWidget);
      expect(find.text(si.matchNoteYouConfirmed), findsOneWidget);
    });
  });

  group('language picker', () {
    testWidgets('lists each language in itself and saves the choice', (tester) async {
      final container = await pumpApp(
        tester,
        const Scaffold(body: LanguageTile()),
      );

      expect(find.text('System default'), findsOneWidget); // the current choice

      await tester.tap(find.byType(LanguageTile));
      await settle(tester);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('සිංහල'), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);

      await tester.tap(find.text('தமிழ்'));
      await settle(tester);

      expect(container.read(localeProvider), const Locale('ta'));
      expect((await SharedPreferences.getInstance()).getString('findora.locale'), 'ta');
      // The tile now names the chosen language, in itself.
      expect(find.text('தமிழ்'), findsOneWidget);
    });
  });
}
