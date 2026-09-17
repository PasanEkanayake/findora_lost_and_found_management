import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../items/data/item_model.dart';
import '../items/data/items_providers.dart';

/// Every item the signed-in user has posted, regardless of status —
/// reachable from ProfileScreen. Unlike the main feed, this shows
/// resolved/claimed items too, with a status badge so the user can tell
/// them apart at a glance.
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
          loading: () => const Center(child: CircularProgressIndicator()),
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

class _MyItemCard extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = item.isLost ? theme.colorScheme.error : theme.colorScheme.tertiary;

    return Card(
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
                  width: 64,
                  height: 64,
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
            ],
          ),
        ),
      ),
    );
  }
}
