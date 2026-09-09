import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'match_model.dart';
import 'matches_repository.dart';

final matchesRepositoryProvider = Provider<MatchesRepository>((ref) {
  return const MatchesRepository();
});

/// autoDispose + `ref.invalidate` after posting an item or acting on a
/// match (see PostItemScreen and MatchesScreen) — matches are created by
/// a database trigger (`record_matches_for_image`), not by this client
/// directly, so a refetch is how the app finds out about them.
final matchesProvider = FutureProvider.autoDispose<List<MatchModel>>((ref) {
  return ref.watch(matchesRepositoryProvider).fetchMyMatches();
});
