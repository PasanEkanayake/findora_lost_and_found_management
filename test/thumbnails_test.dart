import 'package:findora/features/items/data/item_model.dart';
import 'package:findora/features/items/data/thumbnails.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thumbnailPathFor', () {
    test('sits next to the original, prefixed, always .jpg', () {
      expect(thumbnailPathFor('user1/item1/abc-123.jpg'), 'user1/item1/thumb_abc-123.jpg');
    });

    test('a PNG or other original still gets a .jpg thumbnail', () {
      expect(thumbnailPathFor('u/i/photo.png'), 'u/i/thumb_photo.jpg');
      expect(thumbnailPathFor('u/i/photo.JPEG'), 'u/i/thumb_photo.jpg');
    });

    test('only the final extension is dropped', () {
      expect(thumbnailPathFor('u/i/my.photo.v2.jpg'), 'u/i/thumb_my.photo.v2.jpg');
    });

    test('a path with no folder or no extension still works', () {
      expect(thumbnailPathFor('photo.jpg'), 'thumb_photo.jpg');
      expect(thumbnailPathFor('u/i/photo'), 'u/i/thumb_photo.jpg');
    });
  });

  group('ItemModel.thumbnailUrl', () {
    Map<String, dynamic> row(List<Map<String, dynamic>> images) => {
          'id': 'i1',
          'user_id': 'u1',
          'type': 'lost',
          'status': 'open',
          'title': 'Black wallet',
          'created_at': '2026-10-01T10:00:00+00:00',
          'item_images': images,
        };

    test('uses the thumbnail of the first photo when there is one', () {
      final item = ItemModel.fromMap(row([
        {'image_url': 'https://x/full1.jpg', 'thumb_url': 'https://x/thumb_full1.jpg'},
        {'image_url': 'https://x/full2.jpg', 'thumb_url': 'https://x/thumb_full2.jpg'},
      ]));
      expect(item.thumbnailUrl, 'https://x/thumb_full1.jpg');
      // The gallery still gets every full-size photo.
      expect(item.imageUrls, ['https://x/full1.jpg', 'https://x/full2.jpg']);
    });

    test('falls back to the full photo while no thumbnail exists yet', () {
      final item = ItemModel.fromMap(row([
        {'image_url': 'https://x/full1.jpg', 'thumb_url': null},
      ]));
      expect(item.thumbnailUrl, 'https://x/full1.jpg');
    });

    test('a row from before thumbnails (no thumb_url key) still parses', () {
      final item = ItemModel.fromMap(row([
        {'image_url': 'https://x/full1.jpg'},
      ]));
      expect(item.thumbnailUrl, 'https://x/full1.jpg');
    });

    test('a post without photos has no thumbnail', () {
      expect(ItemModel.fromMap(row([])).thumbnailUrl, isNull);
    });
  });
}
