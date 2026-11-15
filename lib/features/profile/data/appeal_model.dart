/// An owner's appeal against a hidden or removed post, as the admin queue
/// sees it. See supabase/32_moderation.sql.
class AppealModel {
  const AppealModel({
    required this.id,
    required this.itemId,
    required this.itemTitle,
    required this.ownerName,
    required this.message,
    required this.createdAt,
    this.itemModerationState,
  });

  final String id;
  final String itemId;
  final String itemTitle;
  final String ownerName;
  final String message;
  final DateTime createdAt;

  /// 'auto_hidden' or 'removed' — why the post is hidden right now.
  final String? itemModerationState;

  factory AppealModel.fromMap(Map<String, dynamic> map) {
    final item = map['items'] as Map<String, dynamic>?;
    final owner = map['owner'] as Map<String, dynamic>?;
    return AppealModel(
      id: map['id'] as String,
      itemId: map['item_id'] as String,
      itemTitle: item?['title'] as String? ?? '(post no longer exists)',
      ownerName: (owner?['full_name'] as String?)?.trim().isNotEmpty == true
          ? owner!['full_name'] as String
          : (owner?['username'] as String? ?? 'Unknown'),
      message: map['message'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      itemModerationState: item?['moderation_state'] as String?,
    );
  }
}
