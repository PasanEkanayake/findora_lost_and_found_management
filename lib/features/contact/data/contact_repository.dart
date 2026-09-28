import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'contact_message_model.dart';
import 'contact_thread_model.dart';

/// Hooks into one open thread's live message list, so code outside
/// [ContactRepository.streamMessages] (sending a message, the screen's
/// periodic sync) can push rows into it. Registered while a stream has a
/// listener, removed when it doesn't.
class _LiveThread {
  const _LiveThread({required this.upsert, required this.syncNewer});

  final void Function(Map<String, dynamic> record) upsert;
  final Future<void> Function() syncNewer;
}

final Map<String, _LiveThread> _liveThreads = {};

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
        current.sort((a, b) => a.createdAt.compareTo(b.createdAt));
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

    /// Fetches only messages newer than what's already on screen. The
    /// realtime channel below is the primary path, but a websocket can be
    /// down (Realtime not enabled for this table — see
    /// supabase/11_realtime_and_matching_fixes.sql — or just a flaky
    /// mobile connection), and without this a message from the other
    /// person would then only show up after reopening the app.
    Future<void> syncNewer() async {
      try {
        DateTime? newest;
        for (final m in current) {
          if (newest == null || m.createdAt.isAfter(newest)) newest = m.createdAt;
        }
        final base = supabase
            .from(AppConstants.contactMessagesTable)
            .select()
            .eq('thread_id', threadId);
        final filtered =
            newest == null ? base : base.gt('created_at', newest.toUtc().toIso8601String());
        final rows = await filtered.order('created_at');
        for (final row in rows as List) {
          upsert(row as Map<String, dynamic>);
        }
      } catch (_) {
        // Best-effort by design — the next tick just tries again.
      }
    }

    controller = StreamController<List<ContactMessageModel>>.broadcast(
      onListen: () {
        _liveThreads[threadId] = _LiveThread(upsert: upsert, syncNewer: syncNewer);
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
            .subscribe((status, error) {
              // If messages ever stop arriving live, this line in the
              // `flutter run` console is the first thing to look at:
              // anything other than `subscribed` means Realtime isn't
              // delivering for this table.
              debugPrint('contact_messages realtime [$threadId]: $status ${error ?? ''}');
            });
      },
      onCancel: () {
        _liveThreads.remove(threadId);
        final ch = channel;
        if (ch != null) supabase.removeChannel(ch);
      },
    );

    return controller.stream;
  }

  /// Pulls in anything newer than what [threadId]'s open screen is
  /// showing. No-op when that thread isn't currently open. Called on a
  /// short timer by ContactChatScreen as a safety net for the realtime
  /// channel.
  Future<void> syncNow(String threadId) async {
    await _liveThreads[threadId]?.syncNewer();
  }

  /// Inserts the message and returns immediately with the stored row,
  /// which is pushed straight into the open thread's list. The sender's
  /// own message therefore appears right away from the insert's own
  /// response, instead of depending on the realtime channel echoing it
  /// back (which is what made messages appear "only after reopening the
  /// app" when Realtime wasn't delivering). If the realtime event for the
  /// same row arrives afterwards, it just replaces the identical entry by
  /// id — no duplicate.
  Future<void> sendMessage({required String threadId, required String content}) async {
    final row = await supabase
        .from(AppConstants.contactMessagesTable)
        .insert({
          'thread_id': threadId,
          'sender_id': supabase.auth.currentUser!.id,
          'content': content,
        })
        .select()
        .single();
    _liveThreads[threadId]?.upsert(row);
  }

  Future<void> markThreadRead(String threadId) async {
    await supabase.rpc('mark_contact_thread_read', params: {'p_thread_id': threadId});
  }
}
