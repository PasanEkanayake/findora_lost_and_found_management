import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/paging/page_result.dart';
import '../../core/widgets/show_more_button.dart';
import '../../core/errors/friendly_error.dart';
import 'admin_moderation_tabs.dart';
import 'data/profile_providers.dart';
import 'data/report_model.dart';
import 'data/user_report_model.dart';
import 'widgets/moderation_note_dialog.dart';

/// Only reachable from ProfileScreen when `myProfileProvider` says
/// `isAdmin`. RLS backs this up server-side too (see
/// supabase/03_rls_policies.sql) — a non-admin who somehow navigated here
/// would just see an empty list, not other users' reports.
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  /// How many open reports to show; grows with "Show more". A dismissal or
  /// removal just refetches this many, so the list shrinks in place.
  int _limit = kListPageSize;

  /// Last data shown, so the list stays visible while a bigger page loads.
  PageResult<ReportModel>? _last;

  Future<void> _dismiss(ReportModel report) async {
    try {
      await ref.read(adminRepositoryProvider).dismissReport(report.id);
      refreshModerationLists(ref);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't dismiss the report.")));
    }
  }

  Future<void> _removeItem(ReportModel report) async {
    final note = await showModerationNoteDialog(
      context,
      title: 'Remove this post?',
      message: '"${report.itemTitle}" will be taken down and the owner told. '
          "It isn't permanently erased, and the owner can appeal.",
      confirmLabel: 'Remove',
    );
    if (note == null || !mounted) return;

    try {
      await ref
          .read(adminRepositoryProvider)
          .removeItem(report.itemId, note: note.isEmpty ? null : note);
      refreshModerationLists(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDatabaseError(e, fallback: "Couldn't remove the post."))),
      );
    }
  }

  /// For a post that reports (or an admin) already hid: bring it back.
  Future<void> _restoreItem(ReportModel report) async {
    final note = await showModerationNoteDialog(
      context,
      title: 'Restore this post?',
      message: '"${report.itemTitle}" becomes visible again, its open reports are '
          'dismissed and the owner is told.',
      confirmLabel: 'Restore',
    );
    if (note == null || !mounted) return;

    try {
      await ref
          .read(adminRepositoryProvider)
          .restoreItem(report.itemId, note: note.isEmpty ? null : note);
      refreshModerationLists(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDatabaseError(e, fallback: "Couldn't restore the post."))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(openReportsProvider(_limit));
    final page = reportsAsync.value ?? _last;
    _last = page;

    final postsBody = Builder(builder: (context) {
          if (page == null) {
            if (reportsAsync.hasError) {
              return const Center(child: Text("Couldn't load reports."));
            }
            return const Center(child: CircularProgressIndicator());
          }
          final reports = page.items;
          if (reports.isEmpty) {
            return const Center(child: Text('No open reports.'));
          }
          // One extra row at the end for the "Show more" button.
          final rowCount = reports.length + (page.hasMore ? 1 : 0);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rowCount,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == reports.length) {
                return ShowMoreButton(
                  loading: reportsAsync.isLoading,
                  onPressed: () => setState(() => _limit += kListPageSize),
                );
              }
              final report = reports[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(report.itemTitle,
                          style: Theme.of(context).textTheme.titleSmall),
                      if (report.itemIsHidden) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.visibility_off_outlined,
                                size: 16, color: Theme.of(context).colorScheme.error),
                            const SizedBox(width: 4),
                            Text(
                              report.itemModerationState == 'auto_hidden'
                                  ? 'Hidden automatically after several reports'
                                  : 'Removed by a moderator',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.error),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text('Reason: ${report.reason}'),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.yMMMd().add_jm().format(report.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      if (report.itemIsHidden) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _restoreItem(report),
                            icon: const Icon(Icons.restore),
                            label: const Text('Restore post'),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _dismiss(report),
                              child: const Text('Dismiss'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => _removeItem(report),
                              child: Text(report.itemModerationState == 'removed'
                                  ? 'Keep removed'
                                  : 'Remove post'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
    });

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Flagged reports'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Posts'),
              Tab(text: 'People'),
              Tab(text: 'Appeals'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            postsBody,
            const _PeopleReports(),
            const AdminAppealsTab(),
            const AdminActivityTab(),
          ],
        ),
      ),
    );
  }
}

/// Reports about people, made from inside chats (see ChatSafetyMenu). Admins
/// can mark one reviewed (acted on) or dismiss it. Taking action against the
/// account itself is done in the Supabase dashboard — the SQL for banning is
/// at the end of supabase/20_chat_safety.sql.
class _PeopleReports extends ConsumerStatefulWidget {
  const _PeopleReports();

  @override
  ConsumerState<_PeopleReports> createState() => _PeopleReportsState();
}

class _PeopleReportsState extends ConsumerState<_PeopleReports> {
  int _limit = kListPageSize;
  PageResult<UserReportModel>? _last;

  Future<void> _resolve(UserReportModel report, String status) async {
    try {
      await ref.read(adminRepositoryProvider).resolveUserReport(report.id, status: status);
      ref.invalidate(openUserReportsProvider);
      ref.invalidate(moderationLogProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't update the report.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(openUserReportsProvider(_limit));
    final page = reportsAsync.value ?? _last;
    _last = page;
    final theme = Theme.of(context);

    if (page == null) {
      if (reportsAsync.hasError) {
        return const Center(child: Text("Couldn't load reports."));
      }
      return const Center(child: CircularProgressIndicator());
    }
    final reports = page.items;
    if (reports.isEmpty) {
      return const Center(child: Text('No open reports about people.'));
    }
    // One extra row at the end for the "Show more" button.
    final rowCount = reports.length + (page.hasMore ? 1 : 0);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rowCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == reports.length) {
          return ShowMoreButton(
            loading: reportsAsync.isLoading,
            onPressed: () => setState(() => _limit += kListPageSize),
          );
        }
        final report = reports[index];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(report.reportedName, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text('Reason: ${report.reason}'),
                    const SizedBox(height: 4),
                    Text(
                      'Reported by ${report.reporterName} · '
                      '${DateFormat.yMMMd().add_jm().format(report.createdAt.toLocal())}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'User id: ${report.reportedUserId}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _resolve(report, 'dismissed'),
                            child: const Text('Dismiss'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _resolve(report, 'reviewed'),
                            child: const Text('Mark reviewed'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
      },
    );
  }
}
