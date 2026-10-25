import 'package:findora/features/profile/data/profile_model.dart';
import 'package:flutter_test/flutter_test.dart';

ProfileModel _profile({
  String? home,
  String? temp,
  DateTime? tempUntil,
  DateTime? changedAt,
}) =>
    ProfileModel(
      id: 'u1',
      rating: 0,
      ratingCount: 0,
      isAdmin: false,
      countryCode: home,
      tempCountryCode: temp,
      tempCountryUntil: tempUntil,
      countryChangedAt: changedAt,
    );

void main() {
  group('activeTempCountry', () {
    test('is the temporary country while it has not expired', () {
      final profile = _profile(
        home: 'LK',
        temp: 'AU',
        tempUntil: DateTime.now().add(const Duration(days: 3)),
      );
      expect(profile.activeTempCountry, 'AU');
    });

    test('is null once it has expired', () {
      final profile = _profile(
        home: 'LK',
        temp: 'AU',
        tempUntil: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(profile.activeTempCountry, isNull);
    });

    test('is null when no temporary country is set, or its end date is missing', () {
      expect(_profile(home: 'LK').activeTempCountry, isNull);
      expect(_profile(home: 'LK', temp: 'AU').activeTempCountry, isNull);
    });
  });

  group('nextCountryChangeAt', () {
    test('is null if the country was never changed', () {
      expect(_profile(home: 'LK').nextCountryChangeAt, isNull);
    });

    test('is 30 days after the last change while that is still in the future', () {
      final changed = DateTime.now().subtract(const Duration(days: 5));
      final next = _profile(home: 'LK', changedAt: changed).nextCountryChangeAt!;
      expect(next.difference(changed).inDays, 30);
      expect(next.isAfter(DateTime.now()), isTrue);
    });

    test('is null once the 30 days have passed', () {
      final changed = DateTime.now().subtract(const Duration(days: 31));
      expect(_profile(home: 'LK', changedAt: changed).nextCountryChangeAt, isNull);
    });
  });

  group('ProfileModel.fromMap', () {
    test('reads the country columns, tolerating their absence', () {
      final full = ProfileModel.fromMap({
        'id': 'u1',
        'rating': 4.5,
        'rating_count': 2,
        'is_admin': false,
        'country_code': 'LK',
        'temp_country_code': 'AU',
        'temp_country_until': '2030-01-01T00:00:00Z',
        'country_changed_at': '2026-10-01T00:00:00Z',
      });
      expect(full.countryCode, 'LK');
      expect(full.tempCountryCode, 'AU');
      expect(full.tempCountryUntil, DateTime.utc(2030));
      expect(full.countryChangedAt, DateTime.utc(2026, 10));

      final bare = ProfileModel.fromMap({
        'id': 'u2',
        'rating': 0,
        'rating_count': 0,
        'is_admin': false,
      });
      expect(bare.countryCode, isNull);
      expect(bare.tempCountryUntil, isNull);
    });
  });
}
