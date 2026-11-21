import 'package:findora/core/paging/page_result.dart';
import 'package:findora/features/profile/data/admin_repository.dart';
import 'package:findora/features/profile/data/appeal_model.dart';
import 'package:findora/features/profile/data/moderated_item_model.dart';
import 'package:findora/features/profile/data/moderation_log_entry.dart';
import 'package:findora/features/profile/data/moderation_repository.dart';
import 'package:findora/features/profile/data/report_model.dart';
import 'package:findora/features/profile/data/user_report_model.dart';

/// An AdminRepository in memory: open reports, open appeals and the audit log,
/// changed by the same actions the real functions perform (restore dismisses a
/// post's reports and upholds its appeal; remove marks its reports reviewed).
class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({
    List<ReportModel>? reports,
    List<AppealModel>? appeals,
    List<ModerationLogEntry>? log,
  })  : reports = reports ?? [],
        appeals = appeals ?? [],
        log = log ?? [];

  final List<ReportModel> reports;
  final List<AppealModel> appeals;
  final List<ModerationLogEntry> log;

  /// What the admin did, in order, e.g. 'restore i1 | note'.
  final List<String> actions = [];

  @override
  Future<PageResult<ReportModel>> fetchOpenReports({int limit = kListPageSize}) async =>
      PageResult.fromFetched(reports.take(limit + 1).toList(), limit);

  @override
  Future<PageResult<UserReportModel>> fetchOpenUserReports({int limit = kListPageSize}) async =>
      const PageResult(items: [], hasMore: false);

  @override
  Future<void> resolveUserReport(String reportId, {required String status}) async {}

  @override
  Future<void> dismissReport(String reportId) async {
    actions.add('dismiss $reportId');
    reports.removeWhere((r) => r.id == reportId);
  }

  @override
  Future<void> removeItem(String itemId, {String? note}) async {
    actions.add('remove $itemId | ${note ?? ''}');
    reports.removeWhere((r) => r.itemId == itemId);
    appeals.removeWhere((a) => a.itemId == itemId);
  }

  @override
  Future<void> restoreItem(String itemId, {String? note}) async {
    actions.add('restore $itemId | ${note ?? ''}');
    reports.removeWhere((r) => r.itemId == itemId);
    appeals.removeWhere((a) => a.itemId == itemId);
  }

  @override
  Future<PageResult<AppealModel>> fetchOpenAppeals({int limit = kListPageSize}) async =>
      PageResult.fromFetched(appeals.take(limit + 1).toList(), limit);

  @override
  Future<void> decideAppeal(String appealId, {required String decision, String? note}) async {
    actions.add('appeal $appealId $decision | ${note ?? ''}');
    appeals.removeWhere((a) => a.id == appealId);
  }

  @override
  Future<PageResult<ModerationLogEntry>> fetchModerationLog({int limit = kListPageSize}) async =>
      PageResult.fromFetched(log.take(limit + 1).toList(), limit);
}

/// The post owner's side: their hidden posts, and appealing one.
class FakeModerationRepository implements ModerationRepository {
  FakeModerationRepository(this.items, {this.submitError});

  List<ModeratedItemModel> items;

  /// If set, submitAppeal throws it (e.g. "You have already appealed").
  final Object? submitError;

  /// (item id, message) for every appeal sent.
  final List<({String itemId, String message})> appeals = [];

  @override
  Future<List<ModeratedItemModel>> fetchMyModeratedItems() async => List.of(items);

  @override
  Future<void> submitAppeal(String itemId, String message) async {
    if (submitError != null) throw submitError!;
    appeals.add((itemId: itemId, message: message));
    items = [
      for (final item in items)
        if (item.itemId == itemId)
          ModeratedItemModel(
            itemId: item.itemId,
            title: item.title,
            itemType: item.itemType,
            moderationState: item.moderationState,
            moderatedAt: item.moderatedAt,
            appealStatus: 'open',
            canAppeal: false,
          )
        else
          item,
    ];
  }
}
