import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/friendly_error.dart';
import '../../core/paging/page_result.dart';
import '../../core/widgets/show_more_button.dart';
import 'data/appeal_model.dart';
import 'data/moderation_log_entry.dart';
import 'data/profile_providers.dart';
import 'widgets/moderation_note_dialog.dart';

/// Refreshes every admin list a moderation action can change.
void refreshModerationLists(WidgetRef ref) {
  ref.invalidate(openReportsProvider);
  ref.invalidate(openAppealsProvider);
  ref.invalidate(moderationLogProvider);
}

/// Owners' appeals against hidden or removed posts, oldest first. Restore
/// brings the post back; Deny needs a reason, which the owner sees. Each
/// decision is logged (see AdminActivityTab).
class AdminAppealsTab extends ConsumerStatefulWidget {
  const AdminAppealsTab({super.key});

  @override
  ConsumerState<AdminAppealsTab> createState() => _AdminAppealsTabState();
}

class _AdminAppealsTabState extends ConsumerState<AdminAppealsTab> {
  int _limit = kListPageSize;
  PageResult<AppealModel>? _last;

  Future<void> _decide(AppealModel appeal, {required bool uphold}) async {
    final note = await showModerationNoteDialog(
      context,
      title: uphold ? 'Restore this post?' : 'Deny this appeal?',
      message: uphold
          ? '"${appeal.itemTitle}" will be visible again and ${appeal.ownerName} is told '
              'the appeal was accepted.'
          : '"${appeal.itemTitle}" stays down for good and ${appeal.ownerName} is told why. '
              'A denied appeal is final.',
      confirmLabel: uphold ? 'Restore' : 'Deny appeal',
      hint: uphold ? 'Note for the owner (optional)' : 'Reason for the owner (required)',
      noteRequired: !uphold,
    );
    if (note == null || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).decideAppeal(
            appeal.id,
            decision: uphold ? 'upheld' : 'denied',
            note: note.isEmpty ? null : note,
          );
      refreshModerationLists(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDatabaseError(e, fallback: "Couldn't save the decision."))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appealsAsync = ref.watch(openAppealsProvider(_limit));
    final page = appealsAsync.value ?? _last;
    _last = page;
    final theme = Theme.of(context);

    if (page == null) {
      if (appealsAsync.hasError) return const Center(child: Text("Couldn't load appeals."));
      return const Center(child: CircularProgressIndicator());
    }
    final appeals = page.items;
    if (appeals.isEmpty) return const Center(child: Text('No open appeals.'));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: appeals.length + (page.hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == appeals.length) {
          return ShowMoreButton(
            loading: appealsAsync.isLoading,
            onPressed: () => setState(() => _limit += kListPageSize),
          );
        }
        final appeal = appeals[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appeal.itemTitle, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${appeal.ownerName} · ${DateFormat.yMMMd().add_jm().format(appeal.createdAt.toLocal())}'
                  '${appeal.itemModerationState == 'removed' ? ' · removed by a moderator' : ' · hidden by reports'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(appeal.message),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _decide(appeal, uphold: false),
                        child: const Text('Deny'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _decide(appeal, uphold: true),
                        child: const Text('Restore post'),
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

/// The audit log: every moderation event, newest first. Read-only — the
/// database refuses edits and deletes (supabase/32_moderation.sql).
class AdminActivityTab extends ConsumerStatefulWidget {
  const AdminActivityTab({super.key});

  @override
  ConsumerState<AdminActivityTab> createState() => _AdminActivityTabState();
}

class _AdminActivityTabState extends ConsumerState<AdminActivityTab> {
  int _limit = kListPageSize;
  PageResult<ModerationLogEntry>? _last;

  (IconData, Color Function(ColorScheme)) _iconFor(String action) => switch (action) {
        'auto_hidden' => (Icons.visibility_off_outlined, (cs) => cs.error),
        'item_removed' => (Icons.delete_outline, (cs) => cs.error),
        'item_restored' || 'appeal_upheld' => (Icons.restore, (cs) => cs.tertiary),
        'appeal_submitted' => (Icons.gavel_outlined, (cs) => cs.primary),
        'appeal_denied' => (Icons.block_outlined, (cs) => cs.error),
        _ => (Icons.flag_outlined, (cs) => cs.onSurfaceVariant),
      };

  @override
  Widget build(BuildContext context) {
    final logAsync = ref.watch(moderationLogProvider(_limit));
    final page = logAsync.value ?? _last;
    _last = page;
    final theme = Theme.of(context);

    if (page == null) {
      if (logAsync.hasError) return const Center(child: Text("Couldn't load the activity log."));
      return const Center(child: CircularProgressIndicator());
    }
    final entries = page.items;
    if (entries.isEmpty) return const Center(child: Text('Nothing logged yet.'));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: entries.length + (page.hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return ShowMoreButton(
            loading: logAsync.isLoading,
            onPressed: () => setState(() => _limit += kListPageSize),
          );
        }
        final entry = entries[index];
        final (icon, colorOf) = _iconFor(entry.action);
        final subtitle = [
          entry.actor,
          if (entry.itemTitle != null) '"${entry.itemTitle}"',
          DateFormat.yMMMd().add_jm().format(entry.createdAt),
        ].join(' · ');
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: colorOf(theme.colorScheme)),
          title: Text(entry.description),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              if (entry.note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Note: ${entry.note}',
                      style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                ),
            ],
          ),
          isThreeLine: entry.note != null,
        );
      },
    );
  }
}
