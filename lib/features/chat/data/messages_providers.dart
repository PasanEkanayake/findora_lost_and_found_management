import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'conversation_model.dart';
import 'message_model.dart';
import 'messages_repository.dart';

final messagesRepositoryProvider = Provider<MessagesRepository>((ref) {
  return const MessagesRepository();
});

/// autoDispose + manual `ref.invalidate` after confirming a match or
/// sending a first message — conversations only appear once a match is
/// confirmed, so this needs to refresh at exactly those two moments.
final conversationsProvider = FutureProvider.autoDispose<List<ConversationModel>>((ref) {
  return ref.watch(messagesRepositoryProvider).fetchConversations();
});

/// A genuine live subscription (unlike itemsFeedProvider/matchesProvider,
/// which refetch on demand) — new messages should appear immediately
/// without the person pulling to refresh a chat mid-conversation.
/// Deliberately NOT autoDispose — see contactMessagesStreamProvider's doc
/// (same pattern in ../../contact/data/contact_providers.dart) for why
/// autoDispose on a live realtime stream causes visible flicker.
final messagesStreamProvider =
    StreamProvider.family<List<MessageModel>, String>((ref, matchId) {
  return ref.watch(messagesRepositoryProvider).streamMessages(matchId);
});
