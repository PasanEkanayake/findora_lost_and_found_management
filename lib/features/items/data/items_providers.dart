import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'category_model.dart';
import 'item_model.dart';
import 'items_repository.dart';
import 'nearby_item_model.dart';

final itemsRepositoryProvider = Provider<ItemsRepository>((ref) {
  return const ItemsRepository();
});

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) {
  return ref.watch(itemsRepositoryProvider).fetchCategories();
});

/// Parameter for [itemsFeedProvider] — a plain value class so Riverpod's
/// `.family` can tell two filter combinations apart and cache/refetch
/// per-combination rather than per-widget.
class ItemsFilter {
  const ItemsFilter({this.categoryId, this.searchQuery});

  final String? categoryId;
  final String? searchQuery;

  @override
  bool operator ==(Object other) =>
      other is ItemsFilter &&
      other.categoryId == categoryId &&
      other.searchQuery == searchQuery;

  @override
  int get hashCode => Object.hash(categoryId, searchQuery);
}

/// autoDispose + manual `ref.invalidate(itemsFeedProvider)` after a
/// successful post (see PostItemScreen) is a simple, honest substitute for
/// a live subscription here — Supabase's `.stream()` API doesn't support
/// the embedded `categories`/`item_images` joins this list needs, so a
/// refetch-on-change approach is the pragmatic choice until Phase 6's
/// messaging work brings in more Realtime plumbing anyway.
///
/// Invalidating the bare `itemsFeedProvider` (no argument) invalidates
/// every cached filter combination, which is what PostItemScreen relies on.
final itemsFeedProvider =
    FutureProvider.autoDispose.family<List<ItemModel>, ItemsFilter>((ref, filter) {
  return ref.watch(itemsRepositoryProvider).fetchOpenItems(
        categoryId: filter.categoryId,
        searchQuery: filter.searchQuery,
      );
});

/// Parameter for [nearbyItemsProvider] — kept as a small local value type
/// instead of depending on google_maps_flutter's LatLng here, so this data
/// layer file doesn't need a map-package import just for equality.
class MapCenter {
  const MapCenter(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is MapCenter && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

final nearbyItemsProvider =
    FutureProvider.autoDispose.family<List<NearbyItemModel>, MapCenter>((ref, center) {
  return ref.watch(itemsRepositoryProvider).fetchNearbyItems(
        latitude: center.latitude,
        longitude: center.longitude,
      );
});

final itemDetailProvider = FutureProvider.autoDispose.family<ItemModel, String>((ref, id) {
  return ref.watch(itemsRepositoryProvider).fetchItemById(id);
});

final myItemsProvider = FutureProvider.autoDispose<List<ItemModel>>((ref) {
  return ref.watch(itemsRepositoryProvider).fetchMyItems();
});
