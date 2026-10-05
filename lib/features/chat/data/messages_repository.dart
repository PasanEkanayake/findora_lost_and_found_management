import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'conversation_model.dart';
import 'message_model.dart';

/// See ContactRepository's `_LiveThread` — same idea, keyed by match id.
class _LiveConversation {
  const _LiveConversation({required this.upsert, required this.syncNewer});

  final void Function(Map<String, dynamic> record) upsert;
  final Future<void> Function() syncNewer;
}

final Map<String, _LiveConversation> _liveConversations = {};

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

  /// Same reasoning and pattern as ContactRepository.streamMessages — see
  /// its doc. `markConversationRead` ticking `read_at` on this same table
  /// is the same kind of self-triggered update event that made a
  /// re-fetch-on-every-change builder flicker.
  Stream<List<MessageModel>> streamMessages(String matchId) {
    final current = <MessageModel>[];
    RealtimeChannel? channel;
    late final StreamController<List<MessageModel>> controller;

    void emit() {
      if (!controller.isClosed) controller.add(List.unmodifiable(current));
    }

    void upsert(Map<String, dynamic> record) {
      final message = MessageModel.fromMap(record);
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
            .from(AppConstants.messagesTable)
            .select()
            .eq('match_id', matchId)
            .order('created_at');
        // See ContactRepository.streamMessages' identical comment: merge
        // via upsert() (not a clear-and-replace) plus a final sort, so a
        // realtime event landing before this fetch resolves can't get
        // silently clobbered or leave the list out of order.
        for (final row in rows as List) {
          upsert(row as Map<String, dynamic>);
        }
        current.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        emit();
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    /// See ContactRepository.streamMessages' `syncNewer` — same safety net
    /// for when the realtime channel isn't delivering.
    Future<void> syncNewer() async {
      try {
        DateTime? newest;
        for (final m in current) {
          if (newest == null || m.createdAt.isAfter(newest)) newest = m.createdAt;
        }
        final base = supabase
            .from(AppConstants.messagesTable)
            .select()
            .eq('match_id', matchId);
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

    controller = StreamController<List<MessageModel>>.broadcast(
      onListen: () {
        _liveConversations[matchId] =
            _LiveConversation(upsert: upsert, syncNewer: syncNewer);
        loadInitial();
        channel = supabase
            .channel('messages:$matchId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: AppConstants.messagesTable,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'match_id',
                value: matchId,
              ),
              callback: (payload) => upsert(payload.newRecord),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: AppConstants.messagesTable,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'match_id',
                value: matchId,
              ),
              callback: (payload) => upsert(payload.newRecord),
            )
            .subscribe((status, error) {
              debugPrint('messages realtime [$matchId]: $status ${error ?? ''}');
            });
      },
      onCancel: () {
        _liveConversations.remove(matchId);
        final ch = channel;
        if (ch != null) supabase.removeChannel(ch);
      },
    );

    return controller.stream;
  }

  /// See ContactRepository.syncNow.
  Future<void> syncNow(String matchId) async {
    await _liveConversations[matchId]?.syncNewer();
  }

  /// See ContactRepository.sendMessage — the stored row is pushed straight
  /// into the open conversation instead of waiting for a realtime echo.
  Future<void> sendMessage({
    required String matchId,
    required String receiverId,
    required String content,
  }) async {
    final row = await supabase
        .from(AppConstants.messagesTable)
        .insert({
          'match_id': matchId,
          'sender_id': supabase.auth.currentUser!.id,
          'receiver_id': receiverId,
          'content': content,
        })
        .select()
        .single();
    _liveConversations[matchId]?.upsert(row);
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
