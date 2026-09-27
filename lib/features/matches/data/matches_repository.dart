import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'match_model.dart';

class MatchesRepository {
  const MatchesRepository();

  /// Calls the `my_matches()` RPC (see
  /// supabase/02_functions_and_triggers.sql), which already resolves each
  /// row into "my item" vs "the matched item" server-side — no client-side
  /// joining needed.
  ///
  /// The RPC only returns the *matched* item's photo, so the caller's own
  /// items' photos are fetched in one extra query — a match card shows both
  /// sides, so it's clear which of your items matched which. That lookup is
  /// cosmetic: if it fails the cards just show the placeholder for your side.
  Future<List<MatchModel>> fetchMyMatches() async {
    final rows = (await supabase.rpc('my_matches') as List<dynamic>)
        .map((row) => row as Map<String, dynamic>)
        .toList();

    final myItemIds = {for (final row in rows) row['my_item_id'] as String}.toList();
    final photoByItemId = <String, String>{};
    if (myItemIds.isNotEmpty) {
      try {
        final itemRows = await supabase
            .from(AppConstants.itemsTable)
            .select('id, item_images(image_url)')
            .inFilter('id', myItemIds);
        for (final itemRow in itemRows) {
          final images = (itemRow['item_images'] as List<dynamic>?) ?? const [];
          if (images.isNotEmpty) {
            photoByItemId[itemRow['id'] as String] =
                (images.first as Map<String, dynamic>)['image_url'] as String;
          }
        }
      } catch (_) {
        // See above — a missing thumbnail must not hide the matches.
      }
    }

    return [
      for (final row in rows)
        MatchModel.fromMap(row, myItemImageUrl: photoByItemId[row['my_item_id'] as String]),
    ];
  }

  Future<void> updateStatus(String matchId, String status) async {
    await supabase
        .from(AppConstants.matchesTable)
        .update({'status': status})
        .eq('id', matchId);
  }
}
