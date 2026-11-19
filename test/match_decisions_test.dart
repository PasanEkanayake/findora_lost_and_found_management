import 'package:findora/features/matches/data/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> row({
    String status = 'pending',
    String? myDecision,
    bool otherConfirmed = false,
    bool reopenable = true,
  }) =>
      {
        'match_id': 'm1',
        'my_item_id': 'a',
        'my_item_title': 'Black wallet',
        'matched_item_id': 'b',
        'matched_item_title': 'Wallet found',
        'matched_item_type': 'found',
        'matched_item_user_id': 'u2',
        'matched_item_image_url': null,
        'my_item_image_url': null,
        'similarity_score': 0.8,
        'image_similarity': null,
        'text_similarity': null,
        'distance_meters': null,
        'time_proximity': null,
        'match_status': status,
        'created_at': '2026-10-01T10:00:00+00:00',
        'my_decision': myDecision,
        'other_confirmed': otherConfirmed,
        'reopenable': reopenable,
      };

  group('two-sided confirmation states', () {
    test('nobody has decided: needs my input, nothing to wait for', () {
      final m = MatchModel.fromMap(row());
      expect(m.needsMyInput, isTrue);
      expect(m.waitingForOther, isFalse);
      expect(m.otherConfirmedFirst, isFalse);
    });

    test('I confirmed, they have not: waiting for the other person', () {
      final m = MatchModel.fromMap(row(myDecision: 'confirmed'));
      expect(m.needsMyInput, isFalse);
      expect(m.waitingForOther, isTrue);
      expect(m.status, 'pending');
    });

    test('they confirmed first: needs my input, and says so', () {
      final m = MatchModel.fromMap(row(otherConfirmed: true));
      expect(m.needsMyInput, isTrue);
      expect(m.otherConfirmedFirst, isTrue);
    });

    test('both confirmed: status is confirmed, not waiting, not needing input', () {
      final m = MatchModel.fromMap(
        row(status: 'confirmed', myDecision: 'confirmed', otherConfirmed: true),
      );
      expect(m.needsMyInput, isFalse);
      expect(m.waitingForOther, isFalse);
      expect(m.otherConfirmedFirst, isFalse);
    });

    test('dismissed by the other person is not reopenable by me', () {
      final m = MatchModel.fromMap(row(status: 'dismissed', reopenable: false));
      expect(m.reopenable, isFalse);
    });

    test('rows without the new columns (older database) read as before', () {
      final map = row()
        ..remove('my_decision')
        ..remove('other_confirmed')
        ..remove('reopenable');
      final m = MatchModel.fromMap(map);
      expect(m.myDecision, isNull);
      expect(m.otherConfirmed, isFalse);
      expect(m.reopenable, isTrue);
      expect(m.needsMyInput, isTrue);
    });
  });
}
