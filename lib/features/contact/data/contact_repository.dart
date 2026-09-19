import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'contact_message_model.dart';
import 'contact_thread_model.dart';

class ContactRepository {
  const ContactRepository();

  /// Creates (or, if one already exists for this item + the signed-in
  /// user, re-opens) a contact thread — see start_contact_thread() in
  /// supabase/06_contact_messaging.sql for the idempotency behavior.
  Future<String> startThread(String itemId) async {
    final result = await supabase.rpc('start_contact_thread', params: {'p_item_id': itemId});
    return result as String;
  }

  Future<List<ContactThreadModel>> fetchThreads() async {
    final rows = await supabase.rpc('my_contact_threads');
    return (rows as List<dynamic>)
        .map((row) => ContactThreadModel.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Stream<List<ContactMessageModel>> streamMessages(String threadId) {
    return supabase
        .from(AppConstants.contactMessagesTable)
        .stream(primaryKey: ['id'])
        .eq('thread_id', threadId)
        .order('created_at')
        .map((rows) => rows.map(ContactMessageModel.fromMap).toList());
  }

  Future<void> sendMessage({required String threadId, required String content}) async {
    await supabase.from(AppConstants.contactMessagesTable).insert({
      'thread_id': threadId,
      'sender_id': supabase.auth.currentUser!.id,
      'content': content,
    });
  }

  Future<void> markThreadRead(String threadId) async {
    await supabase.rpc('mark_contact_thread_read', params: {'p_thread_id': threadId});
  }
}
