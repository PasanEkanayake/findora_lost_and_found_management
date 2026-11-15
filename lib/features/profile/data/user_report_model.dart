/// A report about a PERSON (not a post), made from inside a chat. See
/// supabase/20_chat_safety.sql.
class UserReportModel {
  const UserReportModel({
    required this.id,
    required this.reportedUserId,
    required this.reportedName,
    required this.reporterName,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String reportedUserId;
  final String reportedName;
  final String reporterName;
  final String reason;
  final DateTime createdAt;

  static String _nameOf(Map<String, dynamic>? profile) {
    final fullName = (profile?['full_name'] as String?)?.trim();
    final username = (profile?['username'] as String?)?.trim();
    if (fullName != null && fullName.isNotEmpty) return fullName;
    if (username != null && username.isNotEmpty) return username;
    return 'Findora user';
  }

  factory UserReportModel.fromMap(Map<String, dynamic> map) {
    return UserReportModel(
      id: map['id'] as String,
      reportedUserId: map['reported_user_id'] as String,
      reportedName: _nameOf(map['reported'] as Map<String, dynamic>?),
      reporterName: _nameOf(map['reporter'] as Map<String, dynamic>?),
      reason: map['reason'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
