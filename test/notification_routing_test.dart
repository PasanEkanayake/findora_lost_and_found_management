import 'package:findora/features/notifications/data/notification_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NotificationModel note(String type, {String? itemId = 'item1'}) => NotificationModel(
        id: 'n1',
        type: type,
        title: 'title',
        createdAt: DateTime(2026, 10, 1),
        itemId: itemId,
      );

  group('where tapping a notification goes', () {
    test('matches open the post\'s matches screen, where the confirm button is', () {
      expect(note('new_match').destinationRoute, '/item/item1/matches');
      expect(note('match_waiting').destinationRoute, '/item/item1/matches');
    });

    test('a mutual match (and claims) open the chat list', () {
      expect(note('match_confirmed').destinationRoute, '/chats');
      expect(note('claim_filed').destinationRoute, '/chats');
    });

    test('moderation: owners go to their hidden posts, admins to the queue', () {
      expect(note('post_hidden').destinationRoute, '/profile/hidden-posts');
      expect(note('post_removed').destinationRoute, '/profile/hidden-posts');
      expect(note('appeal_denied').destinationRoute, '/profile/hidden-posts');
      expect(note('post_restored').destinationRoute, '/item/item1');
      expect(note('admin_review').destinationRoute, '/admin/reports');
    });

    test('types that need an item but have none fall back to the chat list', () {
      expect(note('new_match', itemId: null).destinationRoute, '/chats');
      expect(note('post_restored', itemId: null).destinationRoute, '/chats');
    });

    test('a saved-search alert opens the post', () {
      expect(note('saved_search').destinationRoute, '/item/item1');
    });
  });
}
