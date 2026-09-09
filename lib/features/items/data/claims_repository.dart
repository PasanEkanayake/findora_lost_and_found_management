import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'claim_model.dart';

/// Data access for the claim → approve → mark-returned → rate lifecycle
/// that gates a confirmed match's chat (see ChatScreen). Kept separate
/// from ItemsRepository since these methods are specifically about that
/// lifecycle, not general item CRUD.
class ClaimsRepository {
  const ClaimsRepository();

  /// The most recent claim a specific [claimantId] has filed against
  /// [itemId], or null if they haven't filed one (yet, or ever).
  Future<ClaimModel?> fetchClaim({required String itemId, required String claimantId}) async {
    final rows = await supabase
        .from(AppConstants.claimsTable)
        .select()
        .eq('item_id', itemId)
        .eq('claimant_id', claimantId)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return ClaimModel.fromMap(rows.first);
  }

  Future<void> fileClaim({required String itemId, required String verificationAnswer}) async {
    await supabase.from(AppConstants.claimsTable).insert({
      'item_id': itemId,
      'claimant_id': supabase.auth.currentUser!.id,
      'verification_answer': verificationAnswer,
    });
  }

  /// Approving sets the item to 'claimed' automatically via the
  /// `handle_claim_approved` trigger — this call doesn't need to also
  /// touch `items` itself.
  Future<void> updateClaimStatus({required String claimId, required String status}) async {
    await supabase.from(AppConstants.claimsTable).update({'status': status}).eq('id', claimId);
  }

  Future<String> fetchItemStatus(String itemId) async {
    final row =
        await supabase.from(AppConstants.itemsTable).select('status').eq('id', itemId).single();
    return row['status'] as String;
  }

  Future<void> markItemResolved(String itemId) async {
    await supabase.from(AppConstants.itemsTable).update({'status': 'resolved'}).eq('id', itemId);
  }

  Future<void> submitRating({
    required String itemId,
    required String rateeId,
    required int stars,
    String? comment,
  }) async {
    await supabase.from(AppConstants.ratingsTable).insert({
      'item_id': itemId,
      'rater_id': supabase.auth.currentUser!.id,
      'ratee_id': rateeId,
      'stars': stars,
      'comment': comment,
    });
  }

  Future<bool> hasRated({required String itemId, required String raterId}) async {
    final rows = await supabase
        .from(AppConstants.ratingsTable)
        .select('id')
        .eq('item_id', itemId)
        .eq('rater_id', raterId)
        .limit(1);
    return rows.isNotEmpty;
  }
}
