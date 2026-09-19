import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'items_map_view.dart';
import '../../core/providers/auth_providers.dart';
import '../../core/widgets/new_badge.dart';
import '../../core/widgets/shimmer_list.dart';
import '../profile/data/profile_providers.dart';
import '../items/data/category_model.dart';
import '../items/data/item_model.dart';
import '../items/data/items_providers.dart';

/// Whether the Browse tab is currently showing the map instead of the
/// list. Deliberately lives here as a provider rather than as local State
/// on _ItemFeedScreenState: go_router's StatefulShellRoute keeps this
/// screen mounted (just offscreen, inside an IndexedStack) when another
/// bottom-nav tab is showing, so a plain State field would have no way to
/// be reset from outside the widget. MainShell reads/writes this directly
/// so tapping "Browse" in the bottom nav can always force it back to the
/// list view, even if the map was left open — see MainShell's
/// onDestinationSelected.
final feedShowsMapProvider = StateProvider<bool>((ref) => false);

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

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Still up?';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = ItemsFilter(categoryId: _selectedCategoryId, searchQuery: _query);
    final categoriesAsync = ref.watch(categoriesProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final isSignedIn = ref.watch(currentUserProvider) != null;
    final isMapView = ref.watch(feedShowsMapProvider);

    final toggleButton = IconButton(
      icon: Icon(isMapView ? Icons.list_outlined : Icons.map_outlined),
      tooltip: isMapView ? 'Show list' : 'Show map',
      onPressed: () => ref.read(feedShowsMapProvider.notifier).state = !isMapView,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        foregroundColor: Colors.white,
      ),
    );

    if (isMapView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Findora'), actions: [toggleButton]),
        body: const ItemsMapView(),
      );
    }

    final itemsAsync = ref.watch(itemsFeedProvider(filter));
    final firstName = isSignedIn
        ? profileAsync.maybeWhen(
            data: (p) => (p.fullName?.trim().isNotEmpty ?? false)
                ? p.fullName!.trim().split(' ').first
                : null,
            orElse: () => null,
          )
        : null;

    final lostCount = itemsAsync.maybeWhen(
      data: (items) => items.where((i) => i.isLost).length,
      orElse: () => null,
    );
    final foundCount = itemsAsync.maybeWhen(
      data: (items) => items.where((i) => !i.isLost).length,
      orElse: () => null,
    );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(itemsFeedProvider(filter).future),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 196,
              actions: [Padding(padding: const EdgeInsets.only(right: 8), child: toggleButton)],
              flexibleSpace: FlexibleSpaceBar(
                background: _HeroHeader(
                  greeting: _greeting,
                  firstName: firstName,
                  lostCount: lostCount,
                  foundCount: foundCount,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
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
                      const SizedBox(height: 14),
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
                child: ShimmerCardList(),
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
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
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

/// The gradient hero panel behind the app bar — a time-aware greeting plus
/// a one-glance summary of what's currently open, replacing what used to
/// just be a plain "Findora" title over blank space.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.greeting,
    required this.firstName,
    required this.lostCount,
    required this.foundCount,
  });

  final String greeting;
  final String? firstName;
  final int? lostCount;
  final int? foundCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.primary, theme.colorScheme.primaryContainer],
        ),
      ),
      child: Stack(
        children: [
          // A couple of soft translucent circles for texture — cheap to
          // draw, and it's the difference between "gradient rectangle" and
          // something that feels designed.
          Positioned(
            top: -30,
            right: -20,
            child: _softCircle(120, Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: -10,
            right: 60,
            child: _softCircle(60, Colors.white.withValues(alpha: 0.10)),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.travel_explore, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Findora',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    firstName == null ? greeting : '$greeting, $firstName',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lostCount == null
                        ? "Let's find what's missing."
                        : '$lostCount lost · $foundCount found nearby right now',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _softCircle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
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

/// "2m ago" / "3h ago" / "5d ago", falling back to a plain date past a
/// week — noticeably easier to scan in a list than a full timestamp on
/// every card, while staying precise for anything more than a few days old.
String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.MMMd().format(time);
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
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.isLost ? Icons.search : Icons.volunteer_activism_outlined,
                                size: 12,
                                color: statusColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                item.isLost ? 'LOST' : 'FOUND',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (item.categoryName != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              item.categoryName!,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                        if (isRecentlyPosted(item.createdAt)) ...[
                          const SizedBox(width: 6),
                          const NewBadge(dense: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (item.locationLabel != null) ...[
                          Icon(Icons.place_outlined,
                              size: 13, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              item.locationLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          Text(' · ',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                        Text(
                          _relativeTime(item.createdAt),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
