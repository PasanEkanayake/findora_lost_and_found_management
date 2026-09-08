import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../items/data/item_model.dart';
import '../items/data/items_providers.dart';

/// The main "Browse" tab, now reading real rows from Supabase via
/// [itemsFeedProvider] instead of hard-coded demo data. Filtering is still
/// done client-side over the fetched list — Phase 5 is where this becomes
/// a proper server-side search/filter query as the dataset grows.
class ItemFeedScreen extends ConsumerStatefulWidget {
  const ItemFeedScreen({super.key});

  @override
  ConsumerState<ItemFeedScreen> createState() => _ItemFeedScreenState();
}

class _ItemFeedScreenState extends ConsumerState<ItemFeedScreen> {
  String _selectedCategory = 'All';
  String _query = '';

  List<ItemModel> _filter(List<ItemModel> items) {
    return items.where((item) {
      final matchesCategory =
          _selectedCategory == 'All' || item.categoryName == _selectedCategory;
      final matchesQuery = _query.isEmpty ||
          item.title.toLowerCase().contains(_query.toLowerCase()) ||
          (item.description?.toLowerCase().contains(_query.toLowerCase()) ?? false) ||
          (item.locationLabel?.toLowerCase().contains(_query.toLowerCase()) ?? false);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(itemsFeedProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final categoryNames = [
      'All',
      ...categoriesAsync.maybeWhen(
        data: (categories) => categories.map((c) => c.name),
        orElse: () => const <String>[],
      ),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(itemsFeedProvider.future),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Findora'),
              actions: [
                IconButton(icon: const Icon(Icons.tune_outlined), onPressed: () {}),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(112),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'Search by item, place, or keyword',
                          prefixIcon: const Icon(Icons.search),
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: categoryNames.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final category = categoryNames[index];
                            final selected = category == _selectedCategory;
                            return ChoiceChip(
                              label: Text(category),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _selectedCategory = category),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            itemsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SliverFillRemaining(
                child: _FeedMessage(
                  icon: Icons.error_outline,
                  title: "Couldn't load items",
                  body: 'Check your connection and pull down to try again.',
                ),
              ),
              data: (items) {
                final filtered = _filter(items);
                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    child: _FeedMessage(
                      icon: Icons.search_off,
                      title: 'Nothing here yet',
                      body: items.isEmpty
                          ? 'Be the first to report a lost or found item.'
                          : 'Try a different search or category.',
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _ItemCard(item: filtered[index]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final ItemModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = item.isLost ? theme.colorScheme.error : theme.colorScheme.tertiary;

    return Card(
      clipBehavior: Clip.antiAlias,
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
                        child: Icon(
                          Icons.image_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: item.imageUrls.first,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          item.isLost ? 'LOST' : 'FOUND',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.categoryName != null) ...[
                        const SizedBox(width: 8),
                        Text(item.categoryName!, style: theme.textTheme.labelSmall),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(item.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.locationLabel != null) item.locationLabel!,
                      DateFormat.MMMd().add_jm().format(item.createdAt),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
