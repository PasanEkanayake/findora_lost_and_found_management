import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'items_map_view.dart';
import '../items/data/category_model.dart';
import '../items/data/item_model.dart';
import '../items/data/items_providers.dart';

/// The main "Browse" tab: a real Supabase-backed list with server-side
/// category/keyword filtering, plus a map view toggled from the app bar.
class ItemFeedScreen extends ConsumerStatefulWidget {
  const ItemFeedScreen({super.key});

  @override
  ConsumerState<ItemFeedScreen> createState() => _ItemFeedScreenState();
}

class _ItemFeedScreenState extends ConsumerState<ItemFeedScreen> {
  String? _selectedCategoryId;
  String _query = '';
  bool _isMapView = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = ItemsFilter(categoryId: _selectedCategoryId, searchQuery: _query);
    final categoriesAsync = ref.watch(categoriesProvider);

    final toggleButton = IconButton(
      icon: Icon(_isMapView ? Icons.list_outlined : Icons.map_outlined),
      tooltip: _isMapView ? 'Show list' : 'Show map',
      onPressed: () => setState(() => _isMapView = !_isMapView),
    );

    if (_isMapView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Findora'), actions: [toggleButton]),
        body: const ItemsMapView(),
      );
    }

    final itemsAsync = ref.watch(itemsFeedProvider(filter));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(itemsFeedProvider(filter).future),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Findora'),
              actions: [toggleButton],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(112),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      TextField(
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search by item, place, or keyword',
                          prefixIcon: const Icon(Icons.search),
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 36,
                        child: categoriesAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (categories) => _CategoryChipRow(
                            categories: categories,
                            selectedId: _selectedCategoryId,
                            onSelect: (id) => setState(() => _selectedCategoryId = id),
                          ),
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
                if (items.isEmpty) {
                  return SliverFillRemaining(
                    child: _FeedMessage(
                      icon: Icons.search_off,
                      title: 'Nothing here yet',
                      body: (_selectedCategoryId == null && _query.isEmpty)
                          ? 'Be the first to report a lost or found item.'
                          : 'Try a different search or category.',
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _ItemCard(item: items[index]),
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

class _CategoryChipRow extends StatelessWidget {
  const _CategoryChipRow({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<CategoryModel> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: const Text('All'),
            selected: selectedId == null,
            onSelected: (_) => onSelect(null),
          ),
        ),
        for (final category in categories)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(category.name),
              selected: selectedId == category.id,
              onSelected: (_) => onSelect(category.id),
            ),
          ),
      ],
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
      ),
    );
  }
}
