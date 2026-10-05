import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ml/tflite_provider.dart';
import '../../../core/providers/auth_providers.dart';
import '../../items/data/items_providers.dart';
import 'matches_providers.dart';

/// Quietly gives an AI embedding to every one of the signed-in user's photos
/// that doesn't have one yet, once per app session (and again if a different
/// account signs in).
///
/// **Why this runs at app start instead of only when the Matches tab is
/// opened.** A photo can only be embedded on the phone of the person who
/// owns it (the embedding comes from the on-device model, and the database
/// only lets you update your own photos). Matching needs *both* photos of a
/// pair to have an embedding. So if account A's photos were posted before
/// AI matching worked and A never opens the Matches tab, then everyone
/// else's matches against A's items stay empty — even though the other
/// person's own photos are all analysed. Running this as soon as the app
/// opens means every user's older photos are caught up the first time they
/// launch the updated app, whichever screen they land on.
///
/// Each photo that gets its embedding makes the database run the match
/// search for it straight away (trigger
/// `item_images_record_matches_on_embedding`, migration 11), so new matches
/// simply appear for everyone involved.
///
/// Never throws: Riverpod 3 automatically retries a provider that errors,
/// which would re-download and re-embed photos in a loop. Problems are
/// logged with debugPrint instead; the Matches tab's scan button reports
/// them to the person visibly. The value is the number of photos embedded
/// this run.
final embeddingBackfillProvider = FutureProvider<int>((ref) async {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (userId == null) return 0;

  try {
    final repo = ref.read(itemsRepositoryProvider);
    final pending = await repo.fetchMyImagesMissingEmbeddings();
    if (pending.isEmpty) {
      debugPrint('Embedding backfill: nothing to do.');
      return 0;
    }
    debugPrint('Embedding backfill: ${pending.length} photo(s) to analyse.');

    final classifier = await ref.read(tfliteClassifierProvider.future);

    var done = 0;
    for (final image in pending) {
      try {
        await repo.embedExistingImage(
          imageId: image.id,
          imageUrl: image.url,
          classifier: classifier,
        );
        done++;
      } catch (e) {
        debugPrint('Embedding backfill: photo ${image.id} failed: $e');
      }
    }
    debugPrint('Embedding backfill: embedded $done of ${pending.length}.');
    if (done > 0) ref.invalidate(matchesProvider);
    return done;
  } catch (e) {
    debugPrint('Embedding backfill: stopped: $e');
    return 0;
  }
});
