import 'package:findora/features/items/data/item_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 18, 12, 0);

  ItemModel item({String status = 'open', DateTime? expiresAt, bool omitExpiry = false}) {
    return ItemModel.fromMap({
      'id': 'i1',
      'user_id': 'u1',
      'type': 'lost',
      'status': status,
      'title': 'Black wallet',
      'created_at': '2026-08-01T10:00:00+00:00',
      if (!omitExpiry && expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
      'item_images': <Map<String, dynamic>>[],
    });
  }

  group('daysUntilExpiry', () {
    test('rounds up, so the last partial day still counts as a day', () {
      expect(item(expiresAt: now.add(const Duration(days: 5))).daysUntilExpiry(now: now), 5);
      expect(item(expiresAt: now.add(const Duration(days: 5, hours: 1))).daysUntilExpiry(now: now), 6);
      expect(item(expiresAt: now.add(const Duration(hours: 3))).daysUntilExpiry(now: now), 1);
    });

    test('once it has passed: 0, never negative', () {
      expect(item(expiresAt: now.subtract(const Duration(days: 2))).daysUntilExpiry(now: now), 0);
    });

    test('unknown when the query did not include it', () {
      expect(item(omitExpiry: true).daysUntilExpiry(now: now), isNull);
    });
  });

  group('isExpiringWithin', () {
    test('an open post inside the window is expiring', () {
      expect(item(expiresAt: now.add(const Duration(days: 10))).isExpiringWithin(14, now: now), isTrue);
      expect(item(expiresAt: now.add(const Duration(days: 14))).isExpiringWithin(14, now: now), isTrue);
    });

    test('plenty of time left: not expiring', () {
      expect(item(expiresAt: now.add(const Duration(days: 40))).isExpiringWithin(14, now: now), isFalse);
    });

    test('only open posts are nudged — not claimed, resolved or already expired', () {
      final soon = now.add(const Duration(days: 3));
      expect(item(status: 'claimed', expiresAt: soon).isExpiringWithin(14, now: now), isFalse);
      expect(item(status: 'resolved', expiresAt: soon).isExpiringWithin(14, now: now), isFalse);
      expect(item(status: 'expired', expiresAt: soon).isExpiringWithin(14, now: now), isFalse);
    });

    test('unknown expiry: never nudged', () {
      expect(item(omitExpiry: true).isExpiringWithin(14, now: now), isFalse);
    });
  });

  test('isExpired follows the status', () {
    expect(item(status: 'expired').isExpired, isTrue);
    expect(item().isExpired, isFalse);
  });
}
