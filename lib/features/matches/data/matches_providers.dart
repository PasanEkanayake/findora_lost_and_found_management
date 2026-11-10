import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/paging/page_result.dart';
import 'match_model.dart';
import 'matches_repository.dart';

final matchesRepositoryProvider = Provider<MatchesRepository>((ref) {
  return const MatchesRepository();
});

/// Parameter for [matchesProvider] — a value class so Riverpod's `.family`
/// caches and refetches per combination.
class MatchesQuery {
  const MatchesQuery({
    this.section = 'all',
    this.filter = MatchFilter.all,
    this.itemId,
    this.limit = kListPageSize,
  });

  /// 'pending' | 'decided' | 'confirmed' | 'all' — see MatchesRepository.
  final String section;
  final MatchFilter filter;

  /// Only matches involving this post (null = all of the person's matches).
  final String? itemId;

  /// How many rows to show; grows by [kListPageSize] with each "Show more".
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is MatchesQuery &&
      other.section == section &&
      other.filter == filter &&
      other.itemId == itemId &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(section, filter, itemId, limit);
}

/// One page of matches. autoDispose + `ref.invalidate(matchesProvider)` after
/// posting an item or acting on a match (see PostItemScreen and MatchCard) —
/// matches are created by a database trigger, not by this client, so a
/// refetch is how the app finds out about them. Invalidating the bare
/// provider refreshes every live query (the tab's sections, a post's own
/// matches, a post page's "Message" button) at once.
final matchesProvider =
    FutureProvider.autoDispose.family<PageResult<MatchModel>, MatchesQuery>((ref, query) {
  return ref.watch(matchesRepositoryProvider).fetchMatchesPage(
        section: query.section,
        filter: query.filter,
        itemId: query.itemId,
        limit: query.limit,
      );
});
