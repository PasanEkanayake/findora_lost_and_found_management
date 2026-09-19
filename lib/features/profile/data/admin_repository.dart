import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'report_model.dart';

/// Only usable if RLS considers the caller an admin (profiles.is_admin) —
/// see the "admins can view all reports" / "admins can update any item"
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

  /// Soft-delete, same as a user deleting their own post (see
  /// ItemsRepository.deleteItem's doc for why) — RLS no longer grants
  /// `delete` on `items` at all, even to admins (see 08_soft_delete.sql),
  /// so this updates `deleted_at` instead. The "admins can update any
  /// item" policy already covers that.
  ///
  /// Also resolves any other still-open reports against this item: with a
  /// real delete, `reports.item_id`'s cascade used to make them vanish
  /// from [fetchOpenReports] automatically; a soft delete doesn't touch
  /// `reports` at all on its own, so without this they'd sit in the open
  /// queue forever pointing at an item that's already been taken down.
  Future<void> removeItem(String itemId) async {
    await supabase
        .from(AppConstants.itemsTable)
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', itemId);

    await supabase
        .from(AppConstants.reportsTable)
        .update({'status': 'dismissed'})
        .eq('item_id', itemId)
        .eq('status', 'open');
  }
}
