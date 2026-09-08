import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'category_model.dart';
import 'item_model.dart';
import 'items_repository.dart';

final itemsRepositoryProvider = Provider<ItemsRepository>((ref) {
  return const ItemsRepository();
});

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) {
  return ref.watch(itemsRepositoryProvider).fetchCategories();
});

/// autoDispose + manual `ref.invalidate(itemsFeedProvider)` after a
/// successful post (see PostItemScreen) is a simple, honest substitute for
/// a live subscription here — Supabase's `.stream()` API doesn't support
/// the embedded `categories`/`item_images` joins this list needs, so a
/// refetch-on-change approach is the pragmatic choice until Phase 6 brings
/// in more Realtime plumbing anyway.
final itemsFeedProvider = FutureProvider.autoDispose<List<ItemModel>>((ref) {
  return ref.watch(itemsRepositoryProvider).fetchOpenItems();
});
