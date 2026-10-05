import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/data/messages_providers.dart';
import '../../features/contact/data/contact_providers.dart';

/// Total unread messages across both kinds of conversation — confirmed
/// matches (`conversationsProvider`) and direct contact threads
/// (`contactThreadsProvider`) — for the Chats tab's bottom-nav badge.
///
/// Lives here rather than in either feature's own `data/` folder since it
/// depends on both and neither should import the other just for this.
/// Derived from the same two providers the Chats tab itself already
/// watches, so the badge can never disagree with what the list actually
/// shows, and needs no query of its own.
final unreadChatsCountProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationsProvider).maybeWhen(
        data: (list) => list.fold<int>(0, (sum, c) => sum + c.unreadCount),
        orElse: () => 0,
      );
  final contactThreads = ref.watch(contactThreadsProvider).maybeWhen(
        data: (list) => list.fold<int>(0, (sum, t) => sum + t.unreadCount),
        orElse: () => 0,
      );
  return conversations + contactThreads;
});
