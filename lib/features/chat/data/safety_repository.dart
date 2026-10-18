import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';

/// A person the signed-in user has blocked.
class BlockedUser {
  const BlockedUser({required this.userId, required this.name, required this.blockedAt});

  final String userId;
  final String name;
  final DateTime blockedAt;

  factory BlockedUser.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    final fullName = (profile?['full_name'] as String?)?.trim();
    final username = (profile?['username'] as String?)?.trim();
    return BlockedUser(
      userId: map['blocked_id'] as String,
      name: (fullName != null && fullName.isNotEmpty)
          ? fullName
          : (username != null && username.isNotEmpty ? username : 'Findora user'),
      blockedAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// Blocking and reporting people (supabase/20_chat_safety.sql).
class SafetyRepository {
  const SafetyRepository();

  /// Ids of everyone I've blocked. The server refuses messages in both
  /// directions on its own; this list is what lets the app hide the
  /// conversation and match from the lists.
  Future<Set<String>> fetchBlockedIds() async {
    final rows = await supabase.from(AppConstants.userBlocksTable).select('blocked_id');
    return {for (final row in rows) row['blocked_id'] as String};
  }

  Future<List<BlockedUser>> fetchBlockedUsers() async {
    final rows = await supabase
        .from(AppConstants.userBlocksTable)
        .select('blocked_id, created_at, profiles!user_blocks_blocked_id_fkey(full_name, username)')
        .order('created_at', ascending: false);
    return rows.map(BlockedUser.fromMap).toList();
  }

  /// Blocking someone twice is not an error.
  Future<void> block(String userId) async {
    await supabase.from(AppConstants.userBlocksTable).upsert(
      {'blocker_id': supabase.auth.currentUser!.id, 'blocked_id': userId},
      onConflict: 'blocker_id,blocked_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> unblock(String userId) async {
    await supabase
        .from(AppConstants.userBlocksTable)
        .delete()
        .eq('blocker_id', supabase.auth.currentUser!.id)
        .eq('blocked_id', userId);
  }

  /// Reports a person from inside a conversation: pass [matchId] for a match
  /// chat or [threadId] for a direct message thread. The database only
  /// accepts it if you really share that conversation with them, and keeps
  /// one open report per pair of people.
  Future<void> reportUser({
    required String reportedUserId,
    String? matchId,
    String? threadId,
    required String reason,
  }) async {
    await supabase.from(AppConstants.userReportsTable).insert({
      'reporter_id': supabase.auth.currentUser!.id,
      'reported_user_id': reportedUserId,
      'match_id': matchId,
      'thread_id': threadId,
      'reason': reason,
    });
  }
}
