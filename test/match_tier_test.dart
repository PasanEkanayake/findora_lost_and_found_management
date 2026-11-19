import 'package:findora/features/matches/data/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

MatchModel _match({double score = 0.5, double? image, double? text}) => MatchModel(
      matchId: 'm',
      myItemId: 'a',
      myItemTitle: 'Phone',
      matchedItemId: 'b',
      matchedItemTitle: 'phone',
      matchedItemType: 'found',
      matchedItemUserId: 'u',
      similarityScore: score,
      status: 'pending',
      createdAt: DateTime(2026, 10, 6),
      imageSimilarity: image,
      textSimilarity: text,
    );

void main() {
  group('MatchTier.fromScore', () {
    test('boundaries', () {
      expect(MatchTier.fromScore(0.80), MatchTier.strong);
      expect(MatchTier.fromScore(0.799), MatchTier.likely);
      expect(MatchTier.fromScore(0.55), MatchTier.likely);
      expect(MatchTier.fromScore(0.549), MatchTier.possible);
      expect(MatchTier.fromScore(0), MatchTier.possible);
      expect(MatchTier.fromScore(1), MatchTier.strong);
    });
  });

  group('signal agreement', () {
    test('a low photo score exists but does not count as agreeing', () {
      final m = _match(image: 0.35, text: 1.0);
      expect(m.imageSimilarity, isNotNull);
      expect(m.photosAgree, isFalse);
      expect(m.wordingAgrees, isTrue);
    });

    test('photos agree from the matching threshold up', () {
      expect(_match(image: 0.60).photosAgree, isTrue);
      expect(_match(image: 0.599).photosAgree, isFalse);
      expect(_match().photosAgree, isFalse); // no photo comparison at all
    });

    test('wording agrees from 50%', () {
      expect(_match(text: 0.5).wordingAgrees, isTrue);
      expect(_match(text: 0.49).wordingAgrees, isFalse);
      expect(_match().wordingAgrees, isFalse);
    });

    test('tier follows the score', () {
      expect(_match(score: 0.9).tier, MatchTier.strong);
      expect(_match(score: 0.42).tier, MatchTier.possible);
    });
  });
}
