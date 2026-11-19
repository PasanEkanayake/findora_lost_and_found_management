import 'package:findora/features/profile/data/appeal_model.dart';
import 'package:findora/features/profile/data/moderated_item_model.dart';
import 'package:findora/features/profile/data/moderation_log_entry.dart';
import 'package:findora/features/profile/data/report_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReportModel', () {
    Map<String, dynamic> row(Map<String, dynamic>? items) => {
          'id': 'r1',
          'item_id': 'i1',
          'reason': 'spam',
          'status': 'open',
          'created_at': '2026-10-01T10:00:00+00:00',
          'items': items,
        };

    test('a visible post is not hidden', () {
      final r = ReportModel.fromMap(row({'title': 'Wallet', 'moderation_state': null}));
      expect(r.itemIsHidden, isFalse);
    });

    test('an auto-hidden post says so', () {
      final r = ReportModel.fromMap(row({'title': 'Wallet', 'moderation_state': 'auto_hidden'}));
      expect(r.itemIsHidden, isTrue);
      expect(r.itemModerationState, 'auto_hidden');
    });

    test('a report whose post row is missing still parses', () {
      final r = ReportModel.fromMap(row(null));
      expect(r.itemIsHidden, isFalse);
      expect(r.itemTitle, contains('no longer exists'));
    });
  });

  group('ModeratedItemModel', () {
    Map<String, dynamic> row({String? appealStatus, bool canAppeal = true, String? note}) => {
          'item_id': 'i1',
          'title': 'Black wallet',
          'item_type': 'lost',
          'moderation_state': 'auto_hidden',
          'moderated_at': '2026-10-01T10:00:00+00:00',
          'appeal_status': appealStatus,
          'appeal_note': note,
          'can_appeal': canAppeal,
        };

    test('no appeal yet: can appeal', () {
      final m = ModeratedItemModel.fromMap(row());
      expect(m.canAppeal, isTrue);
      expect(m.appealOpen, isFalse);
      expect(m.appealDenied, isFalse);
    });

    test('open appeal', () {
      final m = ModeratedItemModel.fromMap(row(appealStatus: 'open', canAppeal: false));
      expect(m.appealOpen, isTrue);
      expect(m.canAppeal, isFalse);
    });

    test('denied appeal carries the moderator reason', () {
      final m = ModeratedItemModel.fromMap(
        row(appealStatus: 'denied', canAppeal: false, note: 'Contains a phone number.'),
      );
      expect(m.appealDenied, isTrue);
      expect(m.appealNote, 'Contains a phone number.');
    });
  });

  group('AppealModel', () {
    test('uses the full name, falling back to the username', () {
      Map<String, dynamic> row(Map<String, dynamic> owner) => {
            'id': 'a1',
            'item_id': 'i1',
            'message': 'This is my own wallet.',
            'created_at': '2026-10-01T10:00:00+00:00',
            'items': {'title': 'Wallet', 'moderation_state': 'removed'},
            'owner': owner,
          };
      expect(AppealModel.fromMap(row({'full_name': 'Sam Lee', 'username': 'sam'})).ownerName,
          'Sam Lee');
      expect(AppealModel.fromMap(row({'full_name': ' ', 'username': 'sam'})).ownerName, 'sam');
      expect(AppealModel.fromMap(row({'full_name': null, 'username': null})).ownerName,
          'Unknown');
    });
  });

  group('ModerationLogEntry', () {
    Map<String, dynamic> row({
      String kind = 'admin',
      String action = 'item_removed',
      Map<String, dynamic>? actor,
      String? note,
    }) =>
        {
          'id': 7,
          'created_at': '2026-10-01T10:00:00+00:00',
          'actor_kind': kind,
          'action': action,
          'actor': actor,
          'details': {'title': 'Wallet'},
          'note': note,
        };

    test('names the admin who acted', () {
      final e = ModerationLogEntry.fromMap(row(actor: {'full_name': 'Alex', 'username': 'a'}));
      expect(e.actor, 'Alex');
      expect(e.itemTitle, 'Wallet');
      expect(e.description, 'Post removed');
    });

    test('system events read "The system"', () {
      final e = ModerationLogEntry.fromMap(row(kind: 'system', action: 'auto_hidden'));
      expect(e.actor, 'The system');
      expect(e.description, contains('hidden automatically'));
    });

    test('an actor whose account was deleted reads as former', () {
      expect(ModerationLogEntry.fromMap(row()).actor, 'A former admin');
      expect(ModerationLogEntry.fromMap(row(kind: 'owner', action: 'appeal_submitted')).actor,
          'A former user');
    });

    test('unknown actions fall back to the raw action name', () {
      expect(ModerationLogEntry.fromMap(row(action: 'something_new')).description,
          'something_new');
    });
  });
}
