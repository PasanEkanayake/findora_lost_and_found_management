import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_providers.dart';
import 'items_providers.dart';

/// Once per app session (and again if a different account signs in), asks the
/// server to make thumbnails for the signed-in person's own photos that don't
/// have one yet — photos posted before thumbnails existed, or whose first
/// attempt failed. Up to 30 photos per session, in batches of 10, so a huge
/// backlog never turns into a burst of work; the rest follow on later visits.
///
/// Everything here is best effort and silent: a photo without a thumbnail
/// just keeps showing its full image in lists. Never throws — Riverpod 3
/// retries a provider that errors, which would repeat the work in a loop
/// (the same reasoning as `embeddingBackfillProvider`). The value is how many
/// photos were handed to the server.
final thumbnailBackfillProvider = FutureProvider<int>((ref) async {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (userId == null) return 0;

  try {
    final repo = ref.read(itemsRepositoryProvider);
    final missing = await repo.fetchMyImageIdsMissingThumbnails(limit: 30);
    if (missing.isEmpty) return 0;

    for (var start = 0; start < missing.length; start += 10) {
      final end = (start + 10).clamp(0, missing.length);
      await repo.requestThumbnails(imageIds: missing.sublist(start, end));
    }
    debugPrint('Thumbnail backfill: asked for ${missing.length} photo(s).');
    return missing.length;
  } catch (e) {
    debugPrint('Thumbnail backfill skipped: $e');
    return 0;
  }
});
