import 'package:findora/core/location/countries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('country list', () {
    test('codes are unique, two upper-case letters', () {
      final codes = [for (final c in kCountries) c.code];
      expect(codes.toSet().length, codes.length);
      for (final code in codes) {
        expect(RegExp(r'^[A-Z]{2}$').hasMatch(code), isTrue, reason: code);
      }
    });

    test('names are unique and not empty', () {
      final names = [for (final c in kCountries) c.name];
      expect(names.toSet().length, names.length);
      expect(names.every((n) => n.trim().isNotEmpty), isTrue);
    });
  });

  group('lookups', () {
    test('countryName is case-insensitive and null-safe', () {
      expect(countryName('LK'), 'Sri Lanka');
      expect(countryName('lk'), 'Sri Lanka');
      expect(countryName('ZZ'), isNull);
      expect(countryName(null), isNull);
    });

    test('isKnownCountry', () {
      expect(isKnownCountry('us'), isTrue);
      expect(isKnownCountry('USA'), isFalse);
      expect(isKnownCountry(''), isFalse);
      expect(isKnownCountry(null), isFalse);
    });

    test('flagEmoji builds regional-indicator pairs', () {
      expect(flagEmoji('LK'), String.fromCharCodes([0x1F1F1, 0x1F1F0]));
      expect(flagEmoji('lk'), flagEmoji('LK'));
      expect(flagEmoji('L'), '');
      expect(flagEmoji('L1'), '');
      expect(flagEmoji(null), '');
    });

    test('countryLabel combines flag and name, empty for unknown codes', () {
      expect(countryLabel('LK'), '${flagEmoji('LK')} Sri Lanka');
      expect(countryLabel('ZZ'), '');
      expect(countryLabel(null), '');
    });
  });

  group('searchCountries', () {
    test('empty query returns everything', () {
      expect(searchCountries('  ').length, kCountries.length);
    });

    test('matches part of a name, case-insensitively', () {
      final codes = [for (final c in searchCountries('SRI')) c.code];
      expect(codes, contains('LK'));
    });

    test('an exact two-letter code finds its country', () {
      expect([for (final c in searchCountries('lk')) c.code], contains('LK'));
    });

    test('no match gives an empty list', () {
      expect(searchCountries('qqqqqq'), isEmpty);
    });
  });
}
