/// Mirrors one row from the `my_conversations()` RPC — one confirmed
/// match, the other side's item, and a preview of the most recent message.
class ConversationModel {
  const ConversationModel({
    required this.matchId,
    required this.myItemId,
    required this.matchedItemId,
    required this.matchedItemTitle,
    required this.matchedItemType,
    required this.otherUserId,
    required this.unreadCount,
    this.matchedItemImageUrl,
    this.lastMessage,
    this.lastMessageAt,
  });

  final String matchId;
  final String myItemId;
  final String matchedItemId;
  final String matchedItemTitle;
  final String matchedItemType; // 'lost' | 'found'
  final String? matchedItemImageUrl;
  final String otherUserId;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  factory ConversationModel.fromMap(Map<String, dynamic> map) {
    return ConversationModel(
      matchId: map['match_id'] as String,
      myItemId: map['my_item_id'] as String,
      matchedItemId: map['matched_item_id'] as String,
      matchedItemTitle: map['matched_item_title'] as String,
      matchedItemType: map['matched_item_type'] as String,
      matchedItemImageUrl: map['matched_item_image_url'] as String?,
      otherUserId: map['other_user_id'] as String,
      lastMessage: map['last_message'] as String?,
      lastMessageAt: map['last_message_at'] == null
          ? null
          : DateTime.parse(map['last_message_at'] as String),
      unreadCount: (map['unread_count'] as num).toInt(),
    );
  }
}
