import 'package:findora/features/items/data/post_draft.dart';
import 'package:findora/features/profile/data/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PostDraft', () {
    test('round-trips through JSON', () {
      const draft = PostDraft(
        type: 'found',
        title: 'Black wallet',
        description: 'Near the bus stand',
        categoryId: 'cat-1',
        proofQuestion: 'What is inside?',
        proofAnswer: 'A library card',
      );
      final restored = PostDraft.fromJson(draft.toJson())!;
      expect(restored.type, 'found');
      expect(restored.title, 'Black wallet');
      expect(restored.description, 'Near the bus stand');
      expect(restored.categoryId, 'cat-1');
      expect(restored.proofQuestion, 'What is inside?');
      expect(restored.proofAnswer, 'A library card');
    });

    test('a draft with only whitespace is empty and not worth keeping', () {
      const draft = PostDraft(
        type: 'lost',
        title: '  ',
        description: '',
        categoryId: 'cat-1', // a category alone isn't worth restoring
        proofQuestion: '',
        proofAnswer: '',
      );
      expect(draft.isEmpty, isTrue);
    });

    test('garbage from storage is ignored rather than crashing', () {
      expect(PostDraft.fromJson(null), isNull);
      expect(PostDraft.fromJson('text'), isNull);
      expect(PostDraft.fromJson({'type': 'sold', 'title': 'x'}), isNull);
      expect(PostDraft.fromJson({'type': 'lost'})!.title, '');
    });
  });

  group('PersonStanding.describe', () {
    test('new account with no ratings', () {
      final standing = PersonStanding(
        rating: 0,
        ratingCount: 0,
        memberSince: DateTime(2026, 9, 24),
      );
      expect(standing.describe(), contains('no ratings yet'));
      expect(standing.describe(), contains('2026'));
    });

    test('singular and plural ratings', () {
      final one = PersonStanding(rating: 5, ratingCount: 1, memberSince: DateTime(2026, 1, 5));
      final many = PersonStanding(rating: 4.75, ratingCount: 4, memberSince: DateTime(2026, 1, 5));
      expect(one.describe(), contains('★ 5.0 (1 rating)'));
      expect(many.describe(), contains('★ 4.8 (4 ratings)'));
    });
  });
}
