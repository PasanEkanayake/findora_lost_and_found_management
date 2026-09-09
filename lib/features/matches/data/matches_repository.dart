import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'match_model.dart';

class MatchesRepository {
  const MatchesRepository();

  /// Calls the `my_matches()` RPC (see
  /// supabase/02_functions_and_triggers.sql), which already resolves each
  /// row into "my item" vs "the matched item" server-side — no client-side
  /// joining needed.
  Future<List<MatchModel>> fetchMyMatches() async {
    final rows = await supabase.rpc('my_matches');
    return (rows as List<dynamic>)
        .map((row) => MatchModel.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateStatus(String matchId, String status) async {
    await supabase
        .from(AppConstants.matchesTable)
        .update({'status': status})
        .eq('id', matchId);
  }
}
