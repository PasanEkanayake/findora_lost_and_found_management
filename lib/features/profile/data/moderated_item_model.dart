/// One of the signed-in user's own posts that moderation has hidden or
/// removed, with where any appeal stands (`my_moderated_items()` in
/// supabase/32_moderation.sql).
class ModeratedItemModel {
  const ModeratedItemModel({
    required this.itemId,
    required this.title,
    required this.itemType,
    required this.moderationState,
    this.moderatedAt,
    this.appealStatus,
    this.appealNote,
    this.canAppeal = true,
  });

  final String itemId;
  final String title;
  final String itemType; // 'lost' | 'found'

  /// 'auto_hidden' (several reports) or 'removed' (a moderator).
  final String moderationState;
  final DateTime? moderatedAt;

  /// null (no appeal yet) | 'open' | 'upheld' | 'denied'.
  final String? appealStatus;

  /// The moderator's reason, once an appeal is decided.
  final String? appealNote;

  /// Whether the owner may still send an appeal for this hiding.
  final bool canAppeal;

  bool get appealOpen => appealStatus == 'open';
  bool get appealDenied => appealStatus == 'denied';

  factory ModeratedItemModel.fromMap(Map<String, dynamic> map) {
    final at = map['moderated_at'] as String?;
    return ModeratedItemModel(
      itemId: map['item_id'] as String,
      title: map['title'] as String,
      itemType: map['item_type'] as String,
      moderationState: map['moderation_state'] as String,
      moderatedAt: at == null ? null : DateTime.parse(at).toLocal(),
      appealStatus: map['appeal_status'] as String?,
      appealNote: map['appeal_note'] as String?,
      canAppeal: (map['can_appeal'] as bool?) ?? true,
    );
  }
}
