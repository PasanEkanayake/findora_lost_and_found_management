import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'data/profile_providers.dart';
import 'data/report_model.dart';

/// Only reachable from ProfileScreen when `myProfileProvider` says
/// `isAdmin`. RLS backs this up server-side too (see
/// supabase/03_rls_policies.sql) — a non-admin who somehow navigated here
/// would just see an empty list, not other users' reports.
class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  Future<void> _dismiss(WidgetRef ref, BuildContext context, ReportModel report) async {
    try {
      await ref.read(adminRepositoryProvider).dismissReport(report.id);
      ref.invalidate(openReportsProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't dismiss the report.")));
    }
  }

  Future<void> _removeItem(WidgetRef ref, BuildContext context, ReportModel report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this item?'),
        content: Text('"${report.itemTitle}" will be deleted permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminRepositoryProvider).removeItem(report.itemId);
      ref.invalidate(openReportsProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't remove the item.")));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(openReportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Flagged reports')),
      body: reportsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't load reports.")),
        data: (reports) {
          if (reports.isEmpty) {
            return const Center(child: Text('No open reports.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final report = reports[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(report.itemTitle,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text('Reason: ${report.reason}'),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.yMMMd().add_jm().format(report.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _dismiss(ref, context, report),
                              child: const Text('Dismiss'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => _removeItem(ref, context, report),
                              child: const Text('Remove item'),
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
        },
      ),
    );
  }
}
