import 'package:flutter/material.dart';

import '../items/data/feed_options.dart';

/// What the filter sheet closed with.
enum FeedFilterAction { apply, save, manage }

class FeedFilterResult {
  const FeedFilterResult({required this.window, required this.sort, required this.action});

  final FeedWindow window;
  final FeedSort sort;
  final FeedFilterAction action;
}

/// The Browse "Filter & sort" sheet: how recent, what order, and — for alerts —
/// saving the current search.
///
/// [saveDescription] is how the current search reads ("\"wallet\" · Found posts
/// · Sri Lanka"); when null there is nothing worth saving yet (no words and no
/// category) and the sheet says how to get something saveable.
Future<FeedFilterResult?> showFeedFilterSheet(
  BuildContext context, {
  required FeedWindow window,
  required FeedSort sort,
  required String? saveDescription,
}) {
  return showModalBottomSheet<FeedFilterResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FeedFilterSheet(window: window, sort: sort, saveDescription: saveDescription),
  );
}

class _FeedFilterSheet extends StatefulWidget {
  const _FeedFilterSheet({
    required this.window,
    required this.sort,
    required this.saveDescription,
  });

  final FeedWindow window;
  final FeedSort sort;
  final String? saveDescription;

  @override
  State<_FeedFilterSheet> createState() => _FeedFilterSheetState();
}

class _FeedFilterSheetState extends State<_FeedFilterSheet> {
  late FeedWindow _window = widget.window;
  late FeedSort _sort = widget.sort;

  void _close(FeedFilterAction action) {
    Navigator.pop(context, FeedFilterResult(window: _window, sort: _sort, action: action));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = widget.saveDescription;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter & sort', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Posted', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in FeedWindow.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _window == option,
                    onSelected: (_) => setState(() => _window = option),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Sort by', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in FeedSort.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _sort == option,
                    onSelected: (_) => setState(() => _sort = option),
                  ),
              ],
            ),
            if (_sort == FeedSort.nearest) ...[
              const SizedBox(height: 6),
              Text(
                'Uses your phone\'s location. Posts without a location come last.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _window = FeedWindow.any;
                    _sort = FeedSort.newest;
                  }),
                  child: const Text('Reset'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => _close(FeedFilterAction.apply),
                  child: const Text('Apply'),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              children: [
                Icon(Icons.notifications_active_outlined, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Get alerts', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            if (description != null) ...[
              Text(
                'Be alerted when a new post matches:\n$description',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () => _close(FeedFilterAction.save),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save this search'),
              ),
            ] else
              Text(
                'Type a search, or pick a category, then come back here to save it and be '
                'alerted about new matching posts.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _close(FeedFilterAction.manage),
              icon: const Icon(Icons.list_alt_outlined),
              label: const Text('Saved searches'),
            ),
          ],
        ),
      ),
    );
  }
}
