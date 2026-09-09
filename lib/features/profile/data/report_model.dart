/// Mirrors a row in the `reports` table, joined with the reported item's
/// title for display in the admin screen.
class ReportModel {
  const ReportModel({
    required this.id,
    required this.itemId,
    required this.itemTitle,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String itemId;
  final String itemTitle;
  final String reason;
  final String status; // 'open' | 'reviewed' | 'dismissed'
  final DateTime createdAt;

  factory ReportModel.fromMap(Map<String, dynamic> map) {
    final itemMap = map['items'] as Map<String, dynamic>?;
    return ReportModel(
      id: map['id'] as String,
      itemId: map['item_id'] as String,
      itemTitle: itemMap?['title'] as String? ?? '(item no longer exists)',
      reason: map['reason'] as String,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
