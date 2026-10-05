import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'notification_model.dart';

/// Data access for the Notifications tab. Reading and marking-read both go
/// straight through PostgREST rather than an RPC — the RLS policies in
/// supabase/14_notifications.sql ("view your own", "update your own") are
/// enough on their own; only *creating* a notification needs the elevated
/// access a SECURITY DEFINER function gives (see that migration's
/// create_notification()), and this app never creates one from the client.
class NotificationsRepository {
  const NotificationsRepository();

  Future<List<NotificationModel>> fetchMyNotifications() async {
    final rows = await supabase
        .from(AppConstants.notificationsTable)
        .select()
        .order('created_at', ascending: false);
    return rows.map(NotificationModel.fromMap).toList();
  }

  Future<void> markRead(String notificationId) async {
    await supabase
        .from(AppConstants.notificationsTable)
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', notificationId)
        .filter('read_at', 'is', null); // Don't disturb an earlier read_at.
  }

  /// Used by "Mark all as read" — one request instead of one per row.
  Future<void> markAllRead() async {
    await supabase
        .from(AppConstants.notificationsTable)
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', supabase.auth.currentUser!.id)
        .filter('read_at', 'is', null);
  }
}
