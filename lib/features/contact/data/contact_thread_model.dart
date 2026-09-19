/// Mirrors one row from the `my_contact_threads()` RPC (see
/// supabase/06_contact_messaging.sql) — a direct-contact conversation about
/// one item, seen from whichever side the signed-in user is on.
class ContactThreadModel {
  const ContactThreadModel({
    required this.threadId,
    required this.itemId,
    required this.itemTitle,
    required this.otherUserId,
    required this.otherUserName,
    required this.amIOwner,
    required this.unreadCount,
    required this.createdAt,
    this.itemImageUrl,
    this.lastMessage,
    this.lastMessageAt,
  });

  final String threadId;
  final String itemId;
  final String itemTitle;
  final String? itemImageUrl;
  final String otherUserId;
  final String otherUserName;

  /// True if the signed-in user posted the item (i.e. is being contacted);
  /// false if they're the one who reached out.
  final bool amIOwner;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;

  factory ContactThreadModel.fromMap(Map<String, dynamic> map) {
    return ContactThreadModel(
      threadId: map['thread_id'] as String,
      itemId: map['item_id'] as String,
      itemTitle: map['item_title'] as String,
      itemImageUrl: map['item_image_url'] as String?,
      otherUserId: map['other_user_id'] as String,
      otherUserName: map['other_user_name'] as String,
      amIOwner: map['am_i_owner'] as bool,
      lastMessage: map['last_message'] as String?,
      lastMessageAt: map['last_message_at'] == null
          ? null
          : DateTime.parse(map['last_message_at'] as String),
      unreadCount: (map['unread_count'] as num).toInt(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
