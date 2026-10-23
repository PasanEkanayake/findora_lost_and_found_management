/// One row of the append-only moderation audit log
/// (supabase/32_moderation.sql). Admin-only.
class ModerationLogEntry {
  const ModerationLogEntry({
    required this.id,
    required this.createdAt,
    required this.actorKind,
    required this.action,
    this.actorName,
    this.itemTitle,
    this.note,
  });

  final int id;
  final DateTime createdAt;

  /// 'admin' | 'system' | 'owner'.
  final String actorKind;

  /// The admin's (or owner's) name; null for the system, or when that account
  /// was later deleted.
  final String? actorName;

  /// 'auto_hidden', 'item_removed', 'item_restored', 'report_dismissed',
  /// 'report_reviewed', 'user_report_dismissed', 'user_report_reviewed',
  /// 'appeal_submitted', 'appeal_upheld', 'appeal_denied'.
  final String action;

  /// The post's title when the event was logged.
  final String? itemTitle;
  final String? note;

  /// Who did it, in words: "Sam", "The system", "A former admin".
  String get actor {
    if (actorKind == 'system') return 'The system';
    if (actorName != null && actorName!.trim().isNotEmpty) return actorName!;
    return actorKind == 'owner' ? 'A former user' : 'A former admin';
  }

  /// What happened, in words.
  String get description => switch (action) {
        'auto_hidden' => 'Post hidden automatically after several reports',
        'item_removed' => 'Post removed',
        'item_restored' => 'Post restored',
        'report_dismissed' => 'Report dismissed',
        'report_reviewed' => 'Report marked reviewed',
        'user_report_dismissed' => 'Report about a person dismissed',
        'user_report_reviewed' => 'Report about a person marked reviewed',
        'appeal_submitted' => 'Appeal sent',
        'appeal_upheld' => 'Appeal accepted — post restored',
        'appeal_denied' => 'Appeal denied',
        _ => action,
      };

  factory ModerationLogEntry.fromMap(Map<String, dynamic> map) {
    final details = map['details'] as Map<String, dynamic>?;
    final actor = map['actor'] as Map<String, dynamic>?;
    final name = (actor?['full_name'] as String?)?.trim();
    return ModerationLogEntry(
      id: (map['id'] as num).toInt(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      actorKind: map['actor_kind'] as String,
      actorName: (name != null && name.isNotEmpty) ? name : actor?['username'] as String?,
      action: map['action'] as String,
      itemTitle: details?['title'] as String?,
      note: map['note'] as String?,
    );
  }
}
