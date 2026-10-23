import '../../../core/supabase/supabase_client.dart';
import 'moderated_item_model.dart';

/// The post owner's side of moderation: seeing which of their posts were
/// hidden or removed, and appealing (supabase/32_moderation.sql).
class ModerationRepository {
  const ModerationRepository();

  Future<List<ModeratedItemModel>> fetchMyModeratedItems() async {
    final rows = await supabase.rpc('my_moderated_items') as List<dynamic>;
    return [
      for (final row in rows) ModeratedItemModel.fromMap(row as Map<String, dynamic>),
    ];
  }

  /// One appeal per hiding. Throws (with a readable message) if the post
  /// isn't hidden, was already appealed, or the text is the wrong length.
  Future<void> submitAppeal(String itemId, String message) async {
    await supabase.rpc('submit_appeal', params: {
      'p_item_id': itemId,
      'p_message': message,
    });
  }
}
