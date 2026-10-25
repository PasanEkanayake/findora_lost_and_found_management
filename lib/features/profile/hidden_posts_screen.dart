import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/friendly_error.dart';
import 'data/moderated_item_model.dart';
import 'data/profile_providers.dart';

/// The signed-in user's own posts that moderation hid (several people
/// reported them) or removed (a moderator took them down) — with the reason
/// and a way to appeal, once per hiding. Reached from Profile (only shown
/// when there is something to show) and from the alert that tells the owner.
/// See supabase/32_moderation.sql.
class HiddenPostsScreen extends ConsumerWidget {
  const HiddenPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(myModeratedItemsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Hidden posts')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't load your hidden posts.")),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'None of your posts are hidden.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myModeratedItemsProvider.future),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _HiddenPostCard(item: items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _HiddenPostCard extends ConsumerWidget {
  const _HiddenPostCard({required this.item});

  final ModeratedItemModel item;

  Future<void> _appeal(BuildContext context, WidgetRef ref) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _AppealDialog(title: item.title),
    );
    if (message == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(moderationRepositoryProvider).submitAppeal(item.itemId, message);
      ref.invalidate(myModeratedItemsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text("Appeal sent. We'll let you know what we decide.")),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyDatabaseError(e, fallback: "Couldn't send your appeal."))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final byReports = item.moderationState == 'auto_hidden';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.visibility_off_outlined, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    byReports
                        ? 'Hidden after several people reported it'
                        : 'Removed by a moderator',
                    style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            if (item.moderatedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  DateFormat.yMMMd().add_jm().format(item.moderatedAt!),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              byReports
                  ? "While it's hidden, nobody else can see it. A moderator will look at it, "
                      'and you can appeal if you think it was a mistake.'
                  : 'Nobody else can see it. If you think this was a mistake, you can appeal.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (item.appealOpen)
              _Note(
                icon: Icons.hourglass_top_outlined,
                text: "Appeal sent — we'll review it and let you know.",
              )
            else if (item.appealDenied)
              _Note(
                icon: Icons.block_outlined,
                text: 'Appeal denied${item.appealNote == null ? '.' : ': ${item.appealNote}'} '
                    'This decision is final.',
              )
            else if (item.canAppeal)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _appeal(context, ref),
                  icon: const Icon(Icons.gavel_outlined, size: 18),
                  label: const Text('Appeal'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog({required this.title});

  final String title;

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final length = _controller.text.trim().length;
    return length >= 10 && length <= 1000;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Appeal this decision'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell a moderator why "${widget.title}" should be visible. '
            'You can appeal once, so be specific.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Why this was a mistake (10+ characters)'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? () => Navigator.pop(context, _controller.text.trim()) : null,
          child: const Text('Send appeal'),
        ),
      ],
    );
  }
}
