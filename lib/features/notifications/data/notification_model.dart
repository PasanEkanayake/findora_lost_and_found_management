/// Mirrors a row in the `notifications` table
/// (supabase/14_notifications.sql). Covers six event types — see that
/// migration's header for why ordinary chat messages aren't among them.
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    this.body,
    this.itemId,
    this.matchId,
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String? body;

  /// The recipient's own post — every type sets this to *their* item, so
  /// one navigation rule (open this item, or this item's matches) works
  /// the same way regardless of type. See [destinationRoute].
  final String? itemId;
  final String? matchId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  /// Where tapping this notification should go. Matches and claims open
  /// through existing screens rather than needing bespoke routing for
  /// every type — see supabase/14_notifications.sql's header for the
  /// reasoning behind keeping this simple.
  String get destinationRoute => switch (type) {
        'new_match' when itemId != null => '/item/$itemId/matches',
        'item_returned' => '/profile/returned',
        'new_rating' => '/profile/ratings',
        // match_confirmed, claim_filed, claim_approved, claim_rejected,
        // and new_match with no itemId (shouldn't happen, but cheaper to
        // handle than assume away): the relevant chat is always one of
        // the open conversations, so send them to the list rather than
        // needing this row to carry everything ChatScreenArgs does.
        _ => '/chats',
      };

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] as String,
      type: map['type'] as String,
      title: map['title'] as String,
      body: map['body'] as String?,
      itemId: map['item_id'] as String?,
      matchId: map['match_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      readAt:
          map['read_at'] == null ? null : DateTime.parse(map['read_at'] as String).toLocal(),
    );
  }
}
