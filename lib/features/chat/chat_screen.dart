import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/supabase/supabase_client.dart';
import '../../core/widgets/post_link_bar.dart';
import '../items/data/claims_providers.dart';
import '../items/data/items_providers.dart';
import '../matches/data/matches_providers.dart';
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
  Timer? _syncTimer;
  String? _lastMarkedReadId;

  /// Recomputed on demand rather than stored, since it only depends on
  /// [widget.args] (fixed for this screen's lifetime) and the signed-in
  /// user's id (which doesn't change mid-session either) — cheap enough
  /// not to bother caching, and it's needed both in [build] and in the
  /// periodic timer below.
  ChatLifecycleParams get _lifecycleParams {
    final myId = supabase.auth.currentUser?.id;
    return ChatLifecycleParams(
      foundItemId: widget.args.foundItemId,
      claimantId: widget.args.iAmClaimant ? (myId ?? '') : widget.args.otherUserId,
      myId: myId ?? '',
    );
  }

  @override
  void initState() {
    super.initState();
    final repo = ref.read(messagesRepositoryProvider);
    repo.markConversationRead(widget.args.matchId);
    // The message provider stays alive between visits (see
    // messagesStreamProvider), so anything sent while this screen was
    // closed is pulled in straight away instead of after the first tick.
    repo.syncNow(widget.args.matchId);
    // One timer covers both: messages have a realtime channel as their
    // primary path (this is only its safety net — see
    // MessagesRepository.syncNow). chatLifecycleProvider has no push
    // channel of its own at all (see its doc), so this timer is the
    // *only* thing that lets the claim/status banner below update without
    // the person leaving and reopening the chat — the fetch that runs the
    // moment this screen is first built (build() watches it below) covers
    // opening the chat, but not a change the *other* person makes while
    // both of you already have it open.
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      repo.syncNow(widget.args.matchId);
      if (mounted) ref.invalidate(chatLifecycleProvider(_lifecycleParams));
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
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

    // See ContactChatScreen: mark a message read as soon as it arrives
    // while this screen is open, not only when it's next reopened.
    ref.listen(messagesStreamProvider(widget.args.matchId), (previous, next) {
      final messages = next.value;
      if (messages == null || messages.isEmpty) return;
      final latest = messages.last;
      if (latest.senderId != myId && latest.id != _lastMarkedReadId) {
        _lastMarkedReadId = latest.id;
        ref.read(messagesRepositoryProvider).markConversationRead(widget.args.matchId);
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(widget.args.otherItemTitle)),
      body: Column(
        children: [
          // The two posts this match is between — tap either to open it.
          PostLinkBar(
            posts: [
              ChatPostLink(
                caption: 'YOUR POST',
                itemId: widget.args.myItemId,
                fallbackTitle: 'Your post',
              ),
              ChatPostLink(
                caption: 'THEIR POST',
                itemId: widget.args.matchedItemId,
                fallbackTitle: widget.args.otherItemTitle,
              ),
            ],
          ),
          ref.watch(chatLifecycleProvider(_lifecycleParams)).when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (status) => _LifecycleBanner(
                  args: widget.args,
                  status: status,
                  lifecycleParams: _lifecycleParams,
                ),
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
                  IconButton.filled(
                    onPressed: _send,
                    tooltip: 'Send message',
                    icon: const Icon(Icons.send_rounded),
                  ),
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
  const _LifecycleBanner({
    required this.args,
    required this.status,
    required this.lifecycleParams,
  });

  final ChatScreenArgs args;
  final ChatLifecycleStatus status;

  /// Identifies exactly which [chatLifecycleProvider] instance this banner
  /// is showing, so its actions below can invalidate *that one* instead of
  /// the whole family — invalidating the bare provider would also refetch
  /// every other chat screen's claim status open elsewhere in the app for
  /// no reason.
  final ChatLifecycleParams lifecycleParams;

  Future<void> _fileClaim(BuildContext context, WidgetRef ref) async {
    final answer = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _ClaimAnswerDialog(),
    );
    if (answer == null || answer.isEmpty || !context.mounted) return;

    try {
      await ref
          .read(claimsRepositoryProvider)
          .fileClaim(itemId: args.foundItemId, verificationAnswer: answer);
      if (!context.mounted) return;
      ref.invalidate(chatLifecycleProvider(lifecycleParams));
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
      if (!context.mounted) return;
      ref.invalidate(chatLifecycleProvider(lifecycleParams));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't update the claim.")));
    }
  }

  Future<void> _markReturned(BuildContext context, WidgetRef ref) async {
    // Only the finder ever gets this button, so the lost post is the one
    // this chat's *other* person owns — but derive it from the args rather
    // than assuming, the same way [ChatScreenArgs.foundItemId] does.
    final lostItemId = args.iAmClaimant ? args.myItemId : args.matchedItemId;

    try {
      await ref
          .read(claimsRepositoryProvider)
          .markReturned(foundItemId: args.foundItemId, lostItemId: lostItemId);
      if (!context.mounted) return;
      ref.invalidate(chatLifecycleProvider(lifecycleParams));
      // Both posts just left every list — refresh everything that shows
      // them so nothing lingers until the next manual refresh.
      ref.invalidate(itemsFeedProvider);
      ref.invalidate(myItemsProvider);
      ref.invalidate(matchesProvider);
      ref.invalidate(returnedItemsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Marked as returned. Both posts have moved to Profile → Returned items.',
          ),
        ),
      );
    } on PostgrestException catch (e) {
      // The database re-checks the return and explains itself in plain
      // language (e.g. "Approve the other person's claim first") — show that.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't update the item.")));
    }
  }

  Future<void> _rate(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({int stars, String comment})>(
      context: context,
      builder: (dialogContext) => const _RatingDialog(),
    );
    if (result == null || !context.mounted) return;
    final (:stars, :comment) = result;

    try {
      await ref.read(claimsRepositoryProvider).submitRating(
            itemId: args.foundItemId,
            rateeId: args.otherUserId,
            stars: stars,
            comment: comment.isEmpty ? null : comment,
          );
      if (!context.mounted) return;
      ref.invalidate(chatLifecycleProvider(lifecycleParams));
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
    // A single button ("File a claim", "Rate", ...) is left-aligned and
    // sized to its label — see the Align below for why. Reject/Approve is
    // its own separate slot, [pairedAction], because a *pair* of these
    // buttons needs the opposite treatment: full width, matching
    // MatchCard's Confirm/Dismiss row, both for a bigger and more
    // accessible tap target and because Align's unbounded width doesn't
    // give two of them anywhere finite to size themselves against (see
    // that fix's history in git blame if this ever regresses).
    Widget? action;
    Widget? pairedAction;

    if (status.itemStatus == 'resolved') {
      if (status.iHaveRated) {
        message = 'Item marked as returned ✓ — find it in Profile → Returned items.';
      } else {
        message = 'Marked as returned — how did it go? Both posts are now private to the two of you.';
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
        pairedAction = Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _decide(context, ref, 'rejected'),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => _decide(context, ref, 'approved'),
                child: const Text('Approve'),
              ),
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
          if (pairedAction != null) ...[
            const SizedBox(height: 8),
            pairedAction,
          ],
        ],
      ),
    );
  }
}

/// Content of the "File a claim" dialog, as its own widget so its
/// [TextEditingController] is disposed when the dialog closes — tied to
/// *this* dialog's own lifecycle rather than to [_LifecycleBanner], which
/// is a plain (stateless) [ConsumerWidget] rebuilt fresh on every claim
/// status change and so isn't a safe place to own a long-lived controller.
class _ClaimAnswerDialog extends StatefulWidget {
  const _ClaimAnswerDialog();

  @override
  State<_ClaimAnswerDialog> createState() => _ClaimAnswerDialogState();
}

class _ClaimAnswerDialogState extends State<_ClaimAnswerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('File a claim'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Describe a unique detail that proves this is yours',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

/// Content of the "How did it go?" rating dialog — same reasoning as
/// [_ClaimAnswerDialog] for why this owns its controller as a proper
/// [StatefulWidget] instead of a bare [StatefulBuilder] closure.
class _RatingDialog extends StatefulWidget {
  const _RatingDialog();

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  var _stars = 5;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('How did it go?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _stars = i),
                  tooltip: '$i star${i == 1 ? '' : 's'}',
                  icon: Icon(
                    i <= _stars ? Icons.star_rounded : Icons.star_border_rounded,
                    color: theme.colorScheme.secondary,
                  ),
                ),
            ],
          ),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(hintText: 'Add a comment (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (stars: _stars, comment: _commentController.text.trim()),
          ),
          child: const Text('Submit'),
        ),
      ],
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
