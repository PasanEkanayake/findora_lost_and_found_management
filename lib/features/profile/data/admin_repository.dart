import '../../../core/constants/app_constants.dart';
import '../../../core/paging/page_result.dart';
import '../../../core/supabase/supabase_client.dart';
import 'appeal_model.dart';
import 'moderation_log_entry.dart';
import 'report_model.dart';
import 'user_report_model.dart';

/// Only usable if RLS considers the caller an admin (profiles.is_admin) —
/// see the "admins can view all reports" / "admins can update any item"
/// policies in supabase/03_rls_policies.sql. A non-admin calling these
/// just gets empty results or a permission error, not a security hole.
class AdminRepository {
  const AdminRepository();

  /// The newest [limit] open reports about posts, plus whether there are more.
  /// The queue grows with a "Show more" button; asking for `limit + 1` rows is
  /// only how it learns whether another page exists.
  Future<PageResult<ReportModel>> fetchOpenReports({int limit = kListPageSize}) async {
    final rows = await supabase
        .from(AppConstants.reportsTable)
        .select('*, items(title, moderation_state)')
        .eq('status', 'open')
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit + 1);
    return PageResult.fromFetched(rows.map(ReportModel.fromMap).toList(), limit);
  }

  /// The newest [limit] open reports about people, plus whether there are more.
  Future<PageResult<UserReportModel>> fetchOpenUserReports({int limit = kListPageSize}) async {
    final rows = await supabase
        .from(AppConstants.userReportsTable)
        .select(
          '*, reported:profiles!user_reports_reported_user_id_fkey(full_name, username), '
          'reporter:profiles!user_reports_reporter_id_fkey(full_name, username)',
        )
        .eq('status', 'open')
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit + 1);
    return PageResult.fromFetched(rows.map(UserReportModel.fromMap).toList(), limit);
  }

  /// [status] is 'reviewed' (acted on) or 'dismissed' (no action needed).
  Future<void> resolveUserReport(String reportId, {required String status}) async {
    await supabase
        .from(AppConstants.userReportsTable)
        .update({'status': status})
        .eq('id', reportId);
  }

  Future<void> dismissReport(String reportId) async {
    await supabase
        .from(AppConstants.reportsTable)
        .update({'status': 'dismissed'})
        .eq('id', reportId);
  }

  /// Takes a post down (soft delete — nothing is erased) through
  /// `admin_remove_item()` (supabase/32_moderation.sql), which also marks the
  /// post's open reports reviewed, records it in the audit log and tells the
  /// owner (with [note] as the reason, if given).
  Future<void> removeItem(String itemId, {String? note}) async {
    await supabase.rpc('admin_remove_item', params: {
      'p_item_id': itemId,
      'p_note': note,
    });
  }

  /// Brings back a post that was hidden by reports or removed: its open
  /// reports are dismissed, any open appeal is upheld, the owner is told.
  Future<void> restoreItem(String itemId, {String? note}) async {
    await supabase.rpc('admin_restore_item', params: {
      'p_item_id': itemId,
      'p_note': note,
    });
  }

  /// The newest [limit] open appeals, plus whether there are more.
  Future<PageResult<AppealModel>> fetchOpenAppeals({int limit = kListPageSize}) async {
    final rows = await supabase
        .from(AppConstants.appealsTable)
        .select(
          '*, items(title, moderation_state), '
          'owner:profiles!appeals_user_id_fkey(full_name, username)',
        )
        .eq('status', 'open')
        .order('created_at', ascending: true) // oldest first: they've waited longest
        .order('id', ascending: true)
        .limit(limit + 1);
    return PageResult.fromFetched(rows.map(AppealModel.fromMap).toList(), limit);
  }

  /// [decision] is 'upheld' (the post comes back) or 'denied' (it stays down;
  /// [note] is then required and shown to the owner).
  Future<void> decideAppeal(String appealId, {required String decision, String? note}) async {
    await supabase.rpc('admin_decide_appeal', params: {
      'p_appeal_id': appealId,
      'p_decision': decision,
      'p_note': note,
    });
  }

  /// The newest [limit] entries of the audit log, plus whether there are more.
  Future<PageResult<ModerationLogEntry>> fetchModerationLog({int limit = kListPageSize}) async {
    final rows = await supabase
        .from(AppConstants.moderationLogTable)
        .select('*, actor:profiles!moderation_log_actor_id_fkey(full_name, username)')
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit + 1);
    return PageResult.fromFetched(rows.map(ModerationLogEntry.fromMap).toList(), limit);
  }
}
