import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Deliberately not built on `.from(...).stream(...)` (Supabase's
  /// realtime-stream builder) — that re-runs its whole underlying query
  /// on every change event it receives (any insert *or* update, so even
  /// [markThreadRead] ticking `read_at` on old messages triggers one),
  /// re-emitting the entire list fresh each time. Riverpod's
  /// `StreamProvider` briefly shows `AsyncLoading` on some of those
  /// re-emissions, which reads as messages flickering out and back in.
  ///
  /// This builds the stream by hand instead: one initial fetch, then a
  /// raw realtime channel that only ever appends a new row or patches an
  /// existing one in local state — never a wholesale re-fetch — so
  /// there's nothing for a mid-conversation flicker to come from.
  Stream<List<ContactMessageModel>> streamMessages(String threadId) {
    final current = <ContactMessageModel>[];
    RealtimeChannel? channel;
    late final StreamController<List<ContactMessageModel>> controller;

    void emit() {
      if (!controller.isClosed) controller.add(List.unmodifiable(current));
    }

    void upsert(Map<String, dynamic> record) {
      final message = ContactMessageModel.fromMap(record);
      final index = current.indexWhere((m) => m.id == message.id);
      if (index == -1) {
        current.add(message);
      } else {
        current[index] = message;
      }
      emit();
    }

    Future<void> loadInitial() async {
      try {
        final rows = await supabase
            .from(AppConstants.contactMessagesTable)
            .select()
            .eq('thread_id', threadId)
            .order('created_at');
        // Merge rather than replace outright: onListen fires the channel
        // subscription without waiting for this fetch to finish, so a
        // realtime event for a brand-new message could in principle
        // already have been upsert()'d into `current` by the time this
        // resolves — clobbering wholesale would silently drop it.
        for (final row in rows as List) {
          upsert(row as Map<String, dynamic>);
        }
        // Guarantees correct order even if a realtime event's upsert()
        // landed before this loop ran (see the comment above) — cheap
        // insurance since this only runs once, on initial load.
        current.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        emit();
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<List<ContactMessageModel>>.broadcast(
      onListen: () {
        loadInitial();
        channel = supabase
            .channel('contact_messages:$threadId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: AppConstants.contactMessagesTable,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'thread_id',
                value: threadId,
              ),
              callback: (payload) => upsert(payload.newRecord),
            )
            .onPostgresChanges(
              // So a read receipt (markThreadRead setting read_at) patches
              // the affected message bubble in place rather than needing a
              // re-fetch to pick it up.
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: AppConstants.contactMessagesTable,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'thread_id',
                value: threadId,
              ),
              callback: (payload) => upsert(payload.newRecord),
            )
            .subscribe();
      },
      onCancel: () {
        final ch = channel;
        if (ch != null) supabase.removeChannel(ch);
      },
    );

    return controller.stream;
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
