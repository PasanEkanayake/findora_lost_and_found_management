import 'package:findora/features/items/data/items_providers.dart';
import 'package:findora/features/items/data/items_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ItemsRepository.cleanSearchTerm', () {
    test('plain text is kept (trimmed)', () {
      expect(ItemsRepository.cleanSearchTerm('  black wallet '), 'black wallet');
    });

    test('characters that would alter the PostgREST filter are removed', () {
      expect(ItemsRepository.cleanSearchTerm('a,user_id.eq.x'), 'a user id.eq.x');
      expect(ItemsRepository.cleanSearchTerm('x),title.ilike.(%'), 'x  title.ilike.');
      expect(ItemsRepository.cleanSearchTerm(r'say "hi" \ now'), 'say  hi    now');
      expect(ItemsRepository.cleanSearchTerm('50%_off*'), '50  off');
    });

    test('nothing left means no search', () {
      expect(ItemsRepository.cleanSearchTerm(null), isNull);
      expect(ItemsRepository.cleanSearchTerm('   '), isNull);
      expect(ItemsRepository.cleanSearchTerm(',(),'), isNull);
    });
  });

  group('ItemsFilter', () {
    test('type is part of the identity (so each tab caches separately)', () {
      expect(const ItemsFilter(type: 'lost'), const ItemsFilter(type: 'lost'));
      expect(const ItemsFilter(type: 'lost') == const ItemsFilter(type: 'found'), isFalse);
      expect(const ItemsFilter(type: 'lost') == const ItemsFilter(), isFalse);
      expect(const ItemsFilter(type: 'lost').hashCode, const ItemsFilter(type: 'lost').hashCode);
    });
  });
}
