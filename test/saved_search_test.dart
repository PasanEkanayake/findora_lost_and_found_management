import 'package:findora/features/items/data/feed_options.dart';
import 'package:findora/features/items/data/items_providers.dart';
import 'package:findora/features/items/data/saved_search_repository.dart';
import 'package:findora/features/notifications/data/notification_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeedWindow.cutoff', () {
    final now = DateTime.utc(2026, 10, 20, 12);

    test('any has no cutoff', () {
      expect(FeedWindow.any.cutoff(now), isNull);
    });

    test('the other windows reach back from now', () {
      expect(FeedWindow.day.cutoff(now), DateTime.utc(2026, 10, 19, 12));
      expect(FeedWindow.week.cutoff(now), DateTime.utc(2026, 10, 13, 12));
      expect(FeedWindow.month.cutoff(now), DateTime.utc(2026, 9, 20, 12));
    });
  });

  group('ItemsFilter', () {
    test('window, sort and position are part of its identity', () {
      const base = ItemsFilter(country: 'LK');
      expect(base, const ItemsFilter(country: 'LK'));
      expect(base == const ItemsFilter(country: 'LK', window: FeedWindow.week), isFalse);
      expect(base == const ItemsFilter(country: 'LK', sort: FeedSort.oldest), isFalse);
      expect(
        const ItemsFilter(sort: FeedSort.nearest, nearLat: 7.1, nearLng: 80.2) ==
            const ItemsFilter(sort: FeedSort.nearest, nearLat: 7.1, nearLng: 80.3),
        isFalse,
      );
    });

    test('hasNonDefaultOptions drives the filter-button dot', () {
      expect(const ItemsFilter().hasNonDefaultOptions, isFalse);
      expect(const ItemsFilter(window: FeedWindow.day).hasNonDefaultOptions, isTrue);
      expect(const ItemsFilter(sort: FeedSort.oldest).hasNonDefaultOptions, isTrue);
    });
  });

  group('SavedSearch', () {
    test('describe joins the parts that are set', () {
      final label = SavedSearch.describe(
        query: '  wallet ',
        categoryName: 'Keys',
        type: 'found',
        countryCode: 'LK',
      );
      expect(label, contains('"wallet"'));
      expect(label, contains('Keys'));
      expect(label, contains('Found posts'));
      expect(label, contains('Sri Lanka'));
    });

    test('describe leaves out what is not set', () {
      final label = SavedSearch.describe(countryCode: 'LK', categoryName: 'Pets');
      expect(label.contains('"'), isFalse);
      expect(label, contains('Pets'));
      expect(label.contains('Lost posts') || label.contains('Found posts'), isFalse);
    });

    test('fromMap reads the row and its joined category', () {
      final search = SavedSearch.fromMap({
        'id': 's1',
        'query': 'umbrella',
        'category_id': 'c1',
        'categories': {'name': 'Other'},
        'type': null,
        'country_code': 'LK',
        'active': true,
        'created_at': '2026-10-20T10:00:00Z',
      });
      expect(search.query, 'umbrella');
      expect(search.categoryName, 'Other');
      expect(search.type, isNull);
      expect(search.active, isTrue);
      expect(search.label, contains('umbrella'));
    });
  });

  group('saved-search alerts', () {
    NotificationModel alert({String? itemId}) => NotificationModel(
          id: 'n1',
          type: 'saved_search',
          title: 'New found post',
          itemId: itemId,
          createdAt: DateTime(2026, 10, 20),
        );

    test('open the post that matched', () {
      expect(alert(itemId: 'abc').destinationRoute, '/item/abc');
    });

    test('without a post they fall back to the chat list', () {
      expect(alert().destinationRoute, '/chats');
    });
  });
}
