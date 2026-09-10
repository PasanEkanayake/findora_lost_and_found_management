import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/supabase_client.dart';
import '../items/data/claims_providers.dart';
import 'data/message_model.dart';
import 'data/messages_providers.dart';

/// Everything ChatScreen needs, passed via go_router's `extra` — a match
/// id to scope messages to, who the other person is (to address sent
/// messages to), and enough about both items to run the claim lifecycle.
class ChatScreenArgs {
  const ChatScreenArgs({
    required this.matchId,
    required this.otherUserId,
    required this.otherItemTitle,
    required this.myItemId,
    required this.matchedItemId,
    required this.matchedItemType,
  });

  final String matchId;
  final String otherUserId;
  final String otherItemTitle;
  final String myItemId;
  final String matchedItemId;
  final String matchedItemType; // 'lost' | 'found'

  /// Claims are always filed against the item with type 'found' — you
  /// claim something someone found, proving you're the one who lost it.
  String get foundItemId => matchedItemType == 'found' ? matchedItemId : myItemId;

  /// True if *my* item is the 'lost' one, meaning I'm the person trying
  /// to prove the matched (found) item is mine.
  bool get iAmClaimant => matchedItemType == 'found';
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.args});

  final ChatScreenArgs args;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    ref.read(messagesRepositoryProvider).markConversationRead(widget.args.matchId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    try {
      await ref.read(messagesRepositoryProvider).sendMessage(
            matchId: widget.args.matchId,
            receiverId: widget.args.otherUserId,
            content: text,
          );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Message didn't send. Try again.")),
      );
      _controller.text = text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myId = supabase.auth.currentUser?.id;
    final messagesAsync = ref.watch(messagesStreamProvider(widget.args.matchId));
    final lifecycleParams = ChatLifecycleParams(
      foundItemId: widget.args.foundItemId,
      claimantId: widget.args.iAmClaimant ? (myId ?? '') : widget.args.otherUserId,
      myId: myId ?? '',
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.args.otherItemTitle)),
      body: Column(
        children: [
          ref.watch(chatLifecycleProvider(lifecycleParams)).when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (status) => _LifecycleBanner(args: widget.args, status: status),
              ),
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Text(
                  "Couldn't load messages.",
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hello — you two found a match!',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final isMine = message.senderId == myId;
                    return _MessageBubble(message: message, isMine: isMine);
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Message'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The claim → approve → mark-returned → rate lifecycle, shown as a
/// single banner above the message list. Which message and action(s) it
/// shows depends on both [ChatScreenArgs.iAmClaimant] and the current
/// [ChatLifecycleStatus] — see the inline comments below for each branch.
class _LifecycleBanner extends ConsumerWidget {
  const _LifecycleBanner({required this.args, required this.status});

  final ChatScreenArgs args;
  final ChatLifecycleStatus status;

  Future<void> _fileClaim(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final answer = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('File a claim'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Describe a unique detail that proves this is yours',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (answer == null || answer.isEmpty || !context.mounted) return;

    try {
      await ref
          .read(claimsRepositoryProvider)
          .fileClaim(itemId: args.foundItemId, verificationAnswer: answer);
      ref.invalidate(chatLifecycleProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't submit the claim.")));
    }
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, String newStatus) async {
    try {
      await ref
          .read(claimsRepositoryProvider)
          .updateClaimStatus(claimId: status.claim!.id, status: newStatus);
      ref.invalidate(chatLifecycleProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't update the claim.")));
    }
  }

  Future<void> _markReturned(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(claimsRepositoryProvider).markItemResolved(args.foundItemId);
      ref.invalidate(chatLifecycleProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't update the item.")));
    }
  }

  Future<void> _rate(BuildContext context, WidgetRef ref) async {
    var stars = 5;
    final commentController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('How did it go?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => setState(() => stars = i),
                      icon: Icon(
                        i <= stars ? Icons.star_rounded : Icons.star_border_rounded,
                        color: Theme.of(dialogContext).colorScheme.secondary,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(hintText: 'Add a comment (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(claimsRepositoryProvider).submitRating(
            itemId: args.foundItemId,
            rateeId: args.otherUserId,
            stars: stars,
            comment: commentController.text.trim().isEmpty ? null : commentController.text.trim(),
          );
      ref.invalidate(chatLifecycleProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't submit the rating.")));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final claim = status.claim;

    String message;
    Widget? action;

    if (status.itemStatus == 'resolved') {
      if (status.iHaveRated) {
        message = 'Item marked as returned ✓';
      } else {
        message = 'Marked as returned — how did it go?';
        action = FilledButton(
          onPressed: () => _rate(context, ref),
          child: const Text('Rate'),
        );
      }
    } else if (claim == null) {
      if (args.iAmClaimant) {
        message = 'Think this is yours? File a claim to verify it.';
        action = FilledButton(
          onPressed: () => _fileClaim(context, ref),
          child: const Text('File a claim'),
        );
      } else {
        message = "Once they file a claim, you'll be able to review it here.";
      }
    } else if (claim.status == 'pending') {
      if (args.iAmClaimant) {
        message = 'Claim submitted — waiting for review.';
      } else {
        message = 'Claim: "${claim.verificationAnswer}"';
        action = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () => _decide(context, ref, 'rejected'),
              child: const Text('Reject'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _decide(context, ref, 'approved'),
              child: const Text('Approve'),
            ),
          ],
        );
      }
    } else if (claim.status == 'approved') {
      if (args.iAmClaimant) {
        message = 'Claim approved! Arrange the handoff.';
      } else {
        message = 'Claim approved — mark as returned once handed over.';
        action = FilledButton(
          onPressed: () => _markReturned(context, ref),
          child: const Text('Mark as returned'),
        );
      }
    } else {
      message = "That claim wasn't approved.";
      if (args.iAmClaimant) {
        action = OutlinedButton(
          onPressed: () => _fileClaim(context, ref),
          child: const Text('File a new claim'),
        );
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodySmall),
          if (action != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: action),
          ],
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final MessageModel message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.content, style: theme.textTheme.bodyMedium?.copyWith(color: textColor)),
            const SizedBox(height: 2),
            Text(
              DateFormat.jm().format(message.createdAt),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: textColor.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
