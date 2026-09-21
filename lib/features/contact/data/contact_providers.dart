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

/// Deliberately NOT autoDispose, unlike contactThreadsProvider above: this
/// wraps a genuine live Supabase realtime subscription (not a one-shot
/// fetch), and autoDispose tearing it down during any transient moment
/// where its listener count briefly touches zero (a route transition
/// frame, a rebuild — Riverpod's dispose timing here isn't something this
/// screen controls) means the subscription gets fully torn down and
/// re-established from scratch, which visibly flashes: the screen drops
/// back to AsyncLoading for a moment, then repopulates once the new
/// subscription's initial fetch completes — i.e. exactly a "messages
/// appearing and disappearing" symptom. Threads are few and lightweight,
/// so keeping this alive for the app's session is the right tradeoff.
final contactMessagesStreamProvider =
    StreamProvider.family<List<ContactMessageModel>, String>((ref, threadId) {
  return ref.watch(contactRepositoryProvider).streamMessages(threadId);
});
