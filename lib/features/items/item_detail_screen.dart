import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'data/item_model.dart';
import 'data/items_providers.dart';

/// Full detail for one item — reachable by tapping a card in the feed or
/// the map. This was a real gap before Phase 8: there was no way to see a
/// full description or all of an item's photos, and nowhere for the
/// "Report" action to live.
class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemDetailProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report this item',
            onPressed: () => _showReportDialog(context, ref),
          ),
        ],
      ),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't load this item.")),
        data: (item) => _ItemDetailBody(item: item),
      ),
    );
  }

  Future<void> _showReportDialog(BuildContext context, WidgetRef ref) async {
    const reasons = [
      'Spam or scam',
      'Inappropriate content',
      'Doesn\'t look like a real item',
      'Other',
    ];
    var selected = reasons.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Report this item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final reason in reasons)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason),
                  value: reason,
                  groupValue: selected,
                  onChanged: (value) => setState(() => selected = value!),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(itemsRepositoryProvider).fileReport(itemId: itemId, reason: selected);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — a moderator will take a look.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't submit the report. Try again.")),
      );
    }
  }
}

class _ItemDetailBody extends StatelessWidget {
  const _ItemDetailBody({required this.item});

  final ItemModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = item.isLost ? theme.colorScheme.error : theme.colorScheme.tertiary;

    return ListView(
      children: [
        if (item.imageUrls.isEmpty)
          Container(
            height: 260,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Icon(Icons.image_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
          )
        else
          SizedBox(
            height: 260,
            child: PageView(
              children: [
                for (final url in item.imageUrls)
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: theme.colorScheme.surfaceContainerHighest),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.isLost ? 'LOST' : 'FOUND',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: statusColor, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (item.categoryName != null) ...[
                    const SizedBox(width: 8),
                    Chip(label: Text(item.categoryName!)),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(item.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              if (item.description != null && item.description!.isNotEmpty) ...[
                Text(item.description!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
              if (item.locationLabel != null)
                _DetailRow(icon: Icons.location_on_outlined, text: item.locationLabel!),
              _DetailRow(
                icon: Icons.schedule,
                text: DateFormat.yMMMd().add_jm().format(item.createdAt),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
