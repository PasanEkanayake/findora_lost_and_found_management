import 'package:findora/features/chat/data/chat_images.dart';
import 'package:findora/features/chat/data/message_model.dart';
import 'package:findora/features/contact/data/contact_message_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageModel', () {
    Map<String, dynamic> row({String content = 'hi', String? imagePath}) => {
          'id': 'm1',
          'match_id': 'match',
          'sender_id': 'a',
          'receiver_id': 'b',
          'content': content,
          'image_path': imagePath,
          'created_at': '2026-10-01T10:00:00+00:00',
          'read_at': null,
        };

    test('a plain text message has no photo', () {
      final m = MessageModel.fromMap(row());
      expect(m.hasImage, isFalse);
      expect(m.content, 'hi');
    });

    test('a photo-only message has an empty caption and a path', () {
      final m = MessageModel.fromMap(row(content: '', imagePath: 'm/x/y.jpg'));
      expect(m.hasImage, isTrue);
      expect(m.imagePath, 'm/x/y.jpg');
      expect(m.content, isEmpty);
    });

    test('a row from before photos existed (no image_path key) still parses', () {
      final map = row()..remove('image_path');
      expect(MessageModel.fromMap(map).hasImage, isFalse);
    });
  });

  group('ContactMessageModel', () {
    test('reads image_path and tolerates an empty caption', () {
      final m = ContactMessageModel.fromMap({
        'id': 'c1',
        'thread_id': 't',
        'sender_id': 'a',
        'content': '',
        'image_path': 'c/t/f.png',
        'created_at': '2026-10-01T10:00:00+00:00',
        'read_at': null,
      });
      expect(m.hasImage, isTrue);
      expect(m.imagePath, 'c/t/f.png');
    });
  });

  group('ChatKind', () {
    test('first storage folder matches the migration (m = match, c = thread)', () {
      expect(ChatKind.match.folder, 'm');
      expect(ChatKind.thread.folder, 'c');
    });
  });
}
