import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../items/data/item_model.dart';
import '../items/data/items_providers.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/shimmer_list.dart';

/// Every item the signed-in user has posted, regardless of status —
/// reachable from ProfileScreen. Unlike the main feed, this shows
/// resolved/claimed items too, with a status badge so the user can tell
/// them apart at a glance. Swipe a card left to delete it.
class MyItemsScreen extends ConsumerWidget {
  const MyItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(myItemsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My reported items')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myItemsProvider.future),
        child: itemsAsync.when(
          loading: () => const ShimmerCardList(),
          error: (_, __) => Center(
            child: Text(
              "Couldn't load your items.",
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 40,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text("You haven't reported anything yet",
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              'Items you post as lost or found will show up here.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _MyItemCard(item: items[index]),
            );
          },
        ),
      ),
    );
  }
}

class _MyItemCard extends ConsumerWidget {
  const _MyItemCard({required this.item});

  final ItemModel item;

  Color _statusColor(BuildContext context) {
    final theme = Theme.of(context);
    switch (item.status) {
      case 'resolved':
        return theme.colorScheme.tertiary;
      case 'claimed':
      case 'matched':
        return theme.colorScheme.secondary;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  Future<bool> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.delete_outline,
      title: 'Delete this post?',
      message: 'This removes "${item.title}" from Findora — nobody else will be able to see '
          "it or get matched against it anymore. Any chats you've already had about it stay "
          'accessible.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return false;

    try {
      await ref.read(itemsRepositoryProvider).deleteItem(item.id);
      ref.invalidate(itemsFeedProvider);
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't delete this post. Try again.")),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final typeColor = item.isLost ? theme.colorScheme.error : theme.colorScheme.tertiary;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, ref),
      onDismissed: (_) {
        // The delete already happened inside confirmDismiss (so the
        // snackbar on failure has a stable screen to attach to) — this
        // just lets the item's own myItemsProvider entry disappear from
        // the list via a normal invalidate, same as any other mutation.
        ref.invalidate(myItemsProvider);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/item/${item.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: item.imageUrls.isEmpty
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.image_outlined,
                                color: theme.colorScheme.onSurfaceVariant),
                          )
                        : CachedNetworkImage(
                            imageUrl: item.imageUrls.first,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: theme.colorScheme.surfaceContainerHighest),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item.isLost ? 'LOST' : 'FOUND',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: typeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.status[0].toUpperCase() + item.status.substring(1),
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: _statusColor(context), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(item.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.yMMMd().format(item.createdAt),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete post',
                  color: theme.colorScheme.onSurfaceVariant,
                  onPressed: () async {
                    if (await _confirmDelete(context, ref)) {
                      ref.invalidate(myItemsProvider);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
