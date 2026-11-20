import 'package:findora/core/paging/page_result.dart';
import 'package:findora/features/matches/data/match_model.dart';
import 'package:findora/features/matches/data/matches_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PageResult.fromFetched', () {
    test('fewer rows than the limit: everything shown, nothing more', () {
      final page = PageResult<int>.fromFetched([1, 2, 3], 5);
      expect(page.items, [1, 2, 3]);
      expect(page.hasMore, isFalse);
    });

    test('exactly the limit: nothing more (no extra row came back)', () {
      final page = PageResult<int>.fromFetched([1, 2, 3], 3);
      expect(page.items, [1, 2, 3]);
      expect(page.hasMore, isFalse);
    });

    test('one row over the limit: that row is dropped and hasMore is true', () {
      final page = PageResult<int>.fromFetched([1, 2, 3, 4], 3);
      expect(page.items, [1, 2, 3]);
      expect(page.hasMore, isTrue);
    });

    test('empty', () {
      final page = PageResult<int>.fromFetched(const [], 20);
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('MatchesQuery', () {
    test('every field is part of the identity (so each list caches separately)', () {
      const base = MatchesQuery(section: 'pending');
      expect(base, const MatchesQuery(section: 'pending'));
      expect(base.hashCode, const MatchesQuery(section: 'pending').hashCode);
      expect(base == const MatchesQuery(section: 'decided'), isFalse);
      expect(base == const MatchesQuery(section: 'pending', limit: 40), isFalse);
      expect(base == const MatchesQuery(section: 'pending', itemId: 'x'), isFalse);
      expect(
        base == const MatchesQuery(section: 'pending', filter: MatchFilter.both),
        isFalse,
      );
    });

    test('defaults to the first page of everything', () {
      const query = MatchesQuery();
      expect(query.section, 'all');
      expect(query.filter, MatchFilter.all);
      expect(query.itemId, isNull);
      expect(query.limit, kListPageSize);
    });
  });

  group('MatchFilter', () {
    test('sends the values my_matches_page() understands', () {
      expect(MatchFilter.values.map((f) => f.rpcValue).toList(),
          ['all', 'image', 'text', 'both', 'nearby', 'time']);
    });
  });

  group('MatchModel.fromMap', () {
    Map<String, dynamic> row({String? myPhoto}) => {
          'match_id': 'm1',
          'my_item_id': 'a',
          'my_item_title': 'Black wallet',
          'matched_item_id': 'b',
          'matched_item_title': 'Wallet found',
          'matched_item_type': 'found',
          'matched_item_user_id': 'u2',
          'matched_item_image_url': null,
          'my_item_image_url': myPhoto,
          'similarity_score': 0.7,
          'image_similarity': null,
          'text_similarity': 0.6,
          'distance_meters': null,
          'time_proximity': null,
          'match_status': 'pending',
          'created_at': '2026-10-01T10:00:00+00:00',
        };

    test('reads my_item_image_url straight from the row', () {
      expect(MatchModel.fromMap(row(myPhoto: 'https://x/y.jpg')).myItemImageUrl,
          'https://x/y.jpg');
      expect(MatchModel.fromMap(row()).myItemImageUrl, isNull);
    });
  });
}
