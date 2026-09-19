import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'contact_message_model.dart';
import 'contact_repository.dart';
import 'contact_thread_model.dart';

final contactRepositoryProvider = Provider<ContactRepository>((ref) {
  return const ContactRepository();
});

/// autoDispose + manual `ref.invalidate` after starting a new thread —
/// same pattern as conversationsProvider in chat/data/messages_providers.dart.
final contactThreadsProvider = FutureProvider.autoDispose<List<ContactThreadModel>>((ref) {
  return ref.watch(contactRepositoryProvider).fetchThreads();
});

final contactMessagesStreamProvider =
    StreamProvider.autoDispose.family<List<ContactMessageModel>, String>((ref, threadId) {
  return ref.watch(contactRepositoryProvider).streamMessages(threadId);
});
