import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'conversation_model.dart';
import 'message_model.dart';

class MessagesRepository {
  const MessagesRepository();

  /// Calls the `my_conversations()` RPC — one row per confirmed match,
  /// already carrying a message preview and unread count.
  Future<List<ConversationModel>> fetchConversations() async {
    final rows = await supabase.rpc('my_conversations');
    return (rows as List<dynamic>)
        .map((row) => ConversationModel.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// A live Realtime stream, unlike the joined queries elsewhere in this
  /// app — `.stream()` only works against a single table with no embedded
  /// resources, which is exactly what a plain message list is.
  Stream<List<MessageModel>> streamMessages(String matchId) {
    return supabase
        .from(AppConstants.messagesTable)
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId)
        .order('created_at')
        .map((rows) => rows.map(MessageModel.fromMap).toList());
  }

  Future<void> sendMessage({
    required String matchId,
    required String receiverId,
    required String content,
  }) async {
    await supabase.from(AppConstants.messagesTable).insert({
      'match_id': matchId,
      'sender_id': supabase.auth.currentUser!.id,
      'receiver_id': receiverId,
      'content': content,
    });
  }

  /// Marks every unread message *addressed to the caller* in this
  /// conversation as read — the RLS policy only lets a receiver update
  /// their own incoming messages, so this can't accidentally mark the
  /// other person's messages as read on their behalf.
  Future<void> markConversationRead(String matchId) async {
    await supabase
        .from(AppConstants.messagesTable)
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('match_id', matchId)
        .eq('receiver_id', supabase.auth.currentUser!.id)
        .filter('read_at', 'is', null);
  }
}
