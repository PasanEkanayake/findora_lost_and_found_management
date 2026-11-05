import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ml/text_embedding_service.dart';
import 'category_model.dart';
import 'feed_options.dart';
import 'item_model.dart';
import 'saved_search_repository.dart';
import 'items_repository.dart';
import 'nearby_item_model.dart';
import 'returned_item_model.dart';

final itemsRepositoryProvider = Provider<ItemsRepository>((ref) {
  return const ItemsRepository();
});

/// Reads AI_SERVICE_URL once at construction — see TextEmbeddingService's
/// doc for how callers should treat a null/unset URL (not an error, just
/// "text-similarity matching isn't available this session").
final textEmbeddingServiceProvider = Provider<TextEmbeddingService>((ref) {
  return TextEmbeddingService(dotenv.env['AI_SERVICE_URL']);
});

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) {
  return ref.watch(itemsRepositoryProvider).fetchCategories();
});

/// Parameter for [itemsFeedProvider] — a plain value class so Riverpod's
/// `.family` can tell two filter combinations apart and cache/refetch
/// per-combination rather than per-widget.
class ItemsFilter {
  const ItemsFilter({
    this.categoryId,
    this.searchQuery,
    this.type,
    this.country,
    this.window = FeedWindow.any,
    this.sort = FeedSort.newest,
    this.nearLat,
    this.nearLng,
  });

  final String? categoryId;
  final String? searchQuery;

  /// 'lost' | 'found' | null for both. Sent to the server (the feed is paged,
  /// so filtering the loaded list on the phone would hide posts that simply
  /// haven't been loaded yet).
  final String? type;

  /// ISO country code — the feed only shows posts from one country.
  final String? country;

  /// "Posted within" and the sort order. [nearLat]/[nearLng] are the phone's
  /// position (rounded, so the provider isn't rebuilt for every metre of
  /// movement) and only matter for [FeedSort.nearest].
  final FeedWindow window;
  final FeedSort sort;
  final double? nearLat;
  final double? nearLng;

  /// True when something other than the defaults is set (drives the dot on the
  /// filter button).
  bool get hasNonDefaultOptions => window != FeedWindow.any || sort != FeedSort.newest;

  @override
  bool operator ==(Object other) =>
      other is ItemsFilter &&
      other.categoryId == categoryId &&
      other.searchQuery == searchQuery &&
      other.type == type &&
      other.country == country &&
      other.window == window &&
      other.sort == sort &&
      other.nearLat == nearLat &&
      other.nearLng == nearLng;

  @override
  int get hashCode =>
      Object.hash(categoryId, searchQuery, type, country, window, sort, nearLat, nearLng);
}

/// How many posts the feed loads per page.
const kFeedPageSize = 20;

/// The first page of the feed plus the totals shown in the Browse header.
/// [lostCount]/[foundCount] are null if the database function behind them
/// isn't installed yet.
class FeedPage {
  const FeedPage({required this.items, this.lostCount, this.foundCount});

  final List<ItemModel> items;
  final int? lostCount;
  final int? foundCount;
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
///
/// Only the FIRST page lives here, with the header totals fetched alongside
/// it; the screen loads later pages itself as the person scrolls (and
/// forgets them whenever this provider delivers fresh data, so every
/// existing `ref.invalidate(itemsFeedProvider)` still refreshes the feed).
final itemsFeedProvider =
    FutureProvider.autoDispose.family<FeedPage, ItemsFilter>((ref, filter) async {
  final repo = ref.watch(itemsRepositoryProvider);
  final nearest = filter.sort == FeedSort.nearest && filter.nearLat != null && filter.nearLng != null;
  final (items, counts) = await (
    nearest
        ? repo.fetchNearestItems(
            lat: filter.nearLat!,
            lng: filter.nearLng!,
            categoryId: filter.categoryId,
            searchQuery: filter.searchQuery,
            type: filter.type,
            country: filter.country,
            window: filter.window,
            limit: kFeedPageSize,
          )
        : repo.fetchOpenItems(
            categoryId: filter.categoryId,
            searchQuery: filter.searchQuery,
            type: filter.type,
            country: filter.country,
            window: filter.window,
            oldestFirst: filter.sort == FeedSort.oldest,
            limit: kFeedPageSize,
          ),
    repo.fetchFeedCounts(
      categoryId: filter.categoryId,
      searchQuery: filter.searchQuery,
      country: filter.country,
      window: filter.window,
    ),
  ).wait;
  return FeedPage(items: items, lostCount: counts?.lost, foundCount: counts?.found);
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

/// The profile's "Returned items" section. autoDispose, so it refetches
/// each time the screen is opened; also invalidated right after a return
/// is recorded (see ChatScreen's "Mark as returned").
final returnedItemsProvider = FutureProvider.autoDispose<List<ReturnedItemModel>>((ref) {
  return ref.watch(itemsRepositoryProvider).fetchMyReturnedItems();
});

final itemDetailProvider = FutureProvider.autoDispose.family<ItemModel, String>((ref, id) {
  return ref.watch(itemsRepositoryProvider).fetchItemById(id);
});

/// The signed-in owner's own expected answer for a found post's proof
/// question (null for everyone else, and when none was set).
final proofAnswerProvider = FutureProvider.autoDispose.family<String?, String>((ref, itemId) {
  return ref.watch(itemsRepositoryProvider).fetchProofAnswer(itemId);
});

final itemCoordinatesProvider =
    FutureProvider.autoDispose.family<ItemCoordinates?, String>((ref, itemId) {
  return ref.watch(itemsRepositoryProvider).fetchItemCoordinates(itemId);
});

final myItemsProvider = FutureProvider.autoDispose<List<ItemModel>>((ref) {
  return ref.watch(itemsRepositoryProvider).fetchMyItems();
});

final savedSearchRepositoryProvider = Provider<SavedSearchRepository>((ref) {
  return const SavedSearchRepository();
});

/// The signed-in person's saved searches, newest first.
final savedSearchesProvider = FutureProvider.autoDispose<List<SavedSearch>>((ref) {
  return ref.watch(savedSearchRepositoryProvider).fetchAll();
});
