import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'report_model.dart';

/// Only usable if RLS considers the caller an admin (profiles.is_admin) —
/// see the "admins can view all reports" / "admins can delete any item"
/// policies in supabase/03_rls_policies.sql. A non-admin calling these
/// just gets empty results or a permission error, not a security hole.
class AdminRepository {
  const AdminRepository();

  Future<List<ReportModel>> fetchOpenReports() async {
    final rows = await supabase
        .from(AppConstants.reportsTable)
        .select('*, items(title)')
        .eq('status', 'open')
        .order('created_at', ascending: false);
    return rows.map(ReportModel.fromMap).toList();
  }

  Future<void> dismissReport(String reportId) async {
    await supabase
        .from(AppConstants.reportsTable)
        .update({'status': 'dismissed'})
        .eq('id', reportId);
  }

  /// `reports.item_id` has `on delete cascade`, so removing the item also
  /// removes any reports that referenced it — no separate status update
  /// needed for this path.
  Future<void> removeItem(String itemId) async {
    await supabase.from(AppConstants.itemsTable).delete().eq('id', itemId);
  }
}
