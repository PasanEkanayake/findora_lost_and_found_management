import '../../../core/paging/page_result.dart';
import '../../../core/supabase/supabase_client.dart';
import 'match_model.dart';

class MatchesRepository {
  const MatchesRepository();

  /// One page of the signed-in user's matches, from the `my_matches_page()`
  /// RPC (supabase/29_matches_paging.sql). The server filters, orders and
  /// limits; it also returns the caller's own post's first photo, so no second
  /// query is needed.
  ///
  /// [section]: 'pending' (best score first) | 'decided' | 'confirmed' |
  /// 'all' (newest first). [itemId] narrows to matches involving one post.
  /// Returns the newest/best [limit] rows plus whether there are more.
  Future<PageResult<MatchModel>> fetchMatchesPage({
    String section = 'all',
    MatchFilter filter = MatchFilter.all,
    String? itemId,
    int limit = kListPageSize,
  }) async {
    final rows = await supabase.rpc('my_matches_page', params: {
      'p_section': section,
      'p_filter': filter.rpcValue,
      'p_item_id': itemId,
      // One more than needed, only to learn whether a next page exists.
      'p_limit': limit + 1,
    }) as List<dynamic>;
    final matches = [
      for (final row in rows) MatchModel.fromMap(row as Map<String, dynamic>),
    ];
    return PageResult.fromFetched(matches, limit);
  }

  /// Records MY decision on a match: 'confirmed', 'dismissed' or 'pending'
  /// (Undo — clears my decision). Goes through the `decide_match()` function
  /// (supabase/31_two_sided_confirmation.sql) — clients have no direct write
  /// access to `matches` — which checks that the caller owns one side and
  /// refuses to take back a confirmation once a claim exists.
  ///
  /// A match is only 'confirmed' once BOTH people have confirmed, so the
  /// returned value is the match's status afterwards: 'confirmed' (mutual —
  /// the chat is open), 'pending' (still waiting on someone) or 'dismissed'.
  Future<String> decide(String matchId, String decision) async {
    final result = await supabase.rpc('decide_match', params: {
      'p_match_id': matchId,
      'p_status': decision,
    });
    return result as String? ?? decision;
  }
}
