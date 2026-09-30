import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../items/data/item_model.dart';
import '../items/data/items_providers.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/item_photo.dart';
import '../../core/widgets/shimmer_list.dart';

/// The signed-in user's posts that are still in play — open, matched or
/// claimed — reachable from ProfileScreen as "My reported items", with a
/// status badge so the user can tell them apart at a glance. Swipe a card
/// left to delete it.
///
/// A **returned** post doesn't appear here: once an item is handed back,
/// both posts involved move to their own "Returned items" section
/// (see ReturnedItemsScreen) and become private to their two owners —
/// see ItemsRepository.fetchMyItems's doc for why.
class MyItemsScreen extends ConsumerStatefulWidget {
  const MyItemsScreen({super.key});

  @override
  ConsumerState<MyItemsScreen> createState() => _MyItemsScreenState();
}

class _MyItemsScreenState extends ConsumerState<MyItemsScreen> {
  /// Ids removed this session but possibly not yet reflected by
  /// [myItemsProvider] — see [_onDeleted] for why this exists. Never
  /// cleared; it can only ever hold a handful of ids for as long as the
  /// screen stays open; a fresh provider load (screen reopened) starts
  /// with an empty set anyway since state is recreated.
  final Set<String> _removedIds = {};

  /// Hides an item the moment it's confirmed deleted, instead of waiting
  /// for [myItemsProvider] to refetch and return a list without it.
  ///
  /// Without this, `Dismissible.onDismissed` finishing its swipe animation
  /// can still find this item's id in the *old* `items` list if the
  /// network refetch triggered by `ref.invalidate` hasn't resolved by the
  /// next frame — which rebuilds the same `Dismissible` with the same key
  /// right after it already reported itself dismissed. Flutter treats
  /// that as the framework's classic "a dismissed Dismissible is still in
  /// the tree" error. Filtering locally means the card disappears exactly
  /// once, synchronously, regardless of how long the refetch takes.
  void _onDeleted(String itemId) {
    setState(() => _removedIds.add(itemId));
    ref.invalidate(myItemsProvider);
  }

  @override
  Widget build(BuildContext context) {
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
          data: (allItems) {
            final items =
                allItems.where((item) => !_removedIds.contains(item.id)).toList();
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
              itemBuilder: (context, index) =>
                  _MyItemCard(item: items[index], onDeleted: _onDeleted),
            );
          },
        ),
      ),
    );
  }
}

class _MyItemCard extends ConsumerWidget {
  const _MyItemCard({required this.item, required this.onDeleted});

  final ItemModel item;

  /// Called once the item is confirmed deleted on the server — see
  /// [_MyItemsScreenState._onDeleted].
  final ValueChanged<String> onDeleted;

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
        // just needs to make the card disappear, which onDeleted does
        // synchronously (see its doc for why that can't wait on a
        // provider refetch).
        onDeleted(item.id);
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
                    child: ItemPhoto(
                      url: item.imageUrls.isEmpty ? null : item.imageUrls.first,
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
                      onDeleted(item.id);
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
