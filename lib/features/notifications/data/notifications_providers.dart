import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_model.dart';
import 'notifications_repository.dart';

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) => const NotificationsRepository());

/// All of the signed-in user's notifications, newest first. Deliberately
/// NOT autoDispose: NotificationsScreen lives in the bottom-nav IndexedStack
/// (see MainShell), which keeps every tab mounted at once, so this provider
/// is already "kept warm" for the lifetime of the session the normal way —
/// the explicit non-autoDispose mainly documents that intent, and means an
/// in-flight fetch survives a quick tab switch away and back.
final notificationsProvider = FutureProvider<List<NotificationModel>>((ref) {
  return ref.watch(notificationsRepositoryProvider).fetchMyNotifications();
});

/// Derived from [notificationsProvider] rather than its own query — one
/// fetch serves both the list and the bottom-nav badge count, and the two
/// can never disagree with each other since there's only one source of
/// truth. Falls back to 0 while loading or on error, since a nav-bar badge
/// has no good way to show "unknown" and a wrong 0 is far less disruptive
/// than a wrong nonzero.
final unreadNotificationsCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).maybeWhen(
        data: (notifications) => notifications.where((n) => n.isUnread).length,
        orElse: () => 0,
      );
});
