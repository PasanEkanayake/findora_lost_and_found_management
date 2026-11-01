import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/supabase/supabase_client.dart';
import '../../core/widgets/post_link_bar.dart';
import '../../core/errors/friendly_error.dart';
import 'data/messages_repository.dart' show kChatPageSize;
import '../items/widgets/photo_strip.dart' show pickPhotoWithSheet;
import 'data/chat_images.dart';
import 'data/typing_channel.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/claim_answer_dialog.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_safety_menu.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/load_earlier_button.dart';
import 'widgets/safe_send.dart';
import 'widgets/safety_banner.dart';
import '../items/data/claim_attempt_status.dart';
import '../items/data/claims_providers.dart';
import '../profile/data/profile_providers.dart';
import '../items/data/items_providers.dart';
import '../matches/data/matches_providers.dart';
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
  final _picker = ImagePicker();
  late final TypingChannel _typing;
  bool _sendingPhoto = false;
  Timer? _syncTimer;
  String? _lastMarkedReadId;
  bool _noMoreEarlier = false; // set once "Load earlier" runs out of messages

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
    _typing = TypingChannel(
      topic: 'typing:m:${widget.args.matchId}',
      myId: supabase.auth.currentUser?.id ?? '',
    )..start();
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
    _typing.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!await confirmBeforeSending(context, text) || !mounted) return;

    _controller.clear();
    _typing.stopTyping();
    try {
      await ref.read(messagesRepositoryProvider).sendMessage(
            matchId: widget.args.matchId,
            receiverId: widget.args.otherUserId,
            content: text,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyDatabaseError(e, fallback: "Message didn't send. Try again.")),
        ),
      );
      _controller.text = text;
    }
  }

  /// Picks a photo, uploads it to the private chat bucket and sends it as a
  /// message — with whatever is typed in the box as its caption.
  Future<void> _sendPhoto() async {
    if (_sendingPhoto) return;
    final file = await pickPhotoWithSheet(context, _picker);
    if (file == null || !mounted) return;
    final caption = _controller.text.trim();
    if (caption.isNotEmpty && !await confirmBeforeSending(context, caption)) return;
    if (!mounted) return;

    setState(() => _sendingPhoto = true);
    final images = ref.read(chatImagesProvider);
    String? path;
    try {
      path = await images.upload(
        kind: ChatKind.match,
        conversationId: widget.args.matchId,
        file: file,
      );
      await ref.read(messagesRepositoryProvider).sendMessage(
            matchId: widget.args.matchId,
            receiverId: widget.args.otherUserId,
            content: caption,
            imagePath: path,
          );
      _controller.clear();
      _typing.stopTyping();
    } catch (e) {
      if (path != null) unawaited(images.deleteQuietly(path));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyDatabaseError(e, fallback: "Photo didn't send. Try again.")),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingPhoto = false);
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
        _typing.otherSentMessage();
        ref.read(messagesRepositoryProvider).markConversationRead(widget.args.matchId);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args.otherItemTitle),
        actions: [
          ChatSafetyMenu(
            onSuggestMeetup: () {
              _controller.text = kSafeMeetupMessage;
              _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
            },
            otherUserId: widget.args.otherUserId,
            otherUserLabel: 'this person',
            matchId: widget.args.matchId,
          ),
        ],
      ),
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
          const SafetyBanner(),
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
                // A full page loaded means there may be older messages. The
                // list is reversed, so the item one past the newest..oldest
                // run sits at the very top.
                final showEarlier = messages.length >= kChatPageSize && !_noMoreEarlier;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length + (showEarlier ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (showEarlier && index == messages.length) {
                      return LoadEarlierButton(
                        onLoad: () async {
                          final fetched = await ref
                              .read(messagesRepositoryProvider)
                              .loadEarlierMessages(widget.args.matchId, messages.first.createdAt);
                          if (fetched < kChatPageSize && mounted) {
                            setState(() => _noMoreEarlier = true);
                          }
                          return fetched >= kChatPageSize;
                        },
                      );
                    }
                    final message = messages[messages.length - 1 - index];
                    final isMine = message.senderId == myId;
                    return ChatBubble(
                      isMine: isMine,
                      content: message.content,
                      createdAt: message.createdAt,
                      imagePath: message.imagePath,
                    );
                  },
                );
              },
            ),
          ),
          TypingIndicator(typing: _typing.otherTyping),
          ChatComposer(
            controller: _controller,
            onSend: _send,
            onAttachPhoto: _sendPhoto,
            sendingPhoto: _sendingPhoto,
            onChanged: (text) => _typing.typed(text.trim().isNotEmpty),
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

  /// The found post can still be claimed (the database allows it while it is
  /// open or matched — not once another claim was approved, it expired, or it
  /// was returned).
  bool get _postOpenForClaims => status.itemStatus == 'open' || status.itemStatus == 'matched';

  /// Posts a claim is being filed for right now. Stops a second tap on the
  /// banner's button, while the first claim is still being sent, from opening
  /// another form and filing a duplicate (the banner is stateless, so this
  /// lives here).
  static final Set<String> _filing = <String>{};

  Future<void> _fileClaim(BuildContext context, WidgetRef ref) async {
    if (_filing.contains(args.foundItemId)) return;
    // The finder may have set a question only the real owner could answer.
    // Failing to load it just falls back to the generic prompt.
    String? question;
    try {
      question = (await ref.read(itemDetailProvider(args.foundItemId).future)).proofQuestion;
    } catch (_) {}
    if (!context.mounted) return;

    // The limit is enforced by the database; this reads the standing fresh so
    // the form can say which attempt this is (and not open at all when there
    // are none left or a wait is running).
    final attempts = await ref.read(claimsRepositoryProvider).fetchAttemptStatus(args.foundItemId);
    if (!context.mounted) return;
    if (attempts != null && (attempts.isLocked || attempts.waitMinutes() != null)) {
      ref.invalidate(chatLifecycleProvider(lifecycleParams));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(claimRejectedMessage(attempts))),
      );
      return;
    }

    final answer = await showClaimAnswerDialog(
      context,
      question: question,
      attempts: attempts,
      // A rejected answer won't be accepted the second time, and each try
      // counts: stop the same words being sent twice.
      previousAnswer: status.claim?.verificationAnswer,
    );
    if (answer == null || answer.isEmpty || !context.mounted) return;

    _filing.add(args.foundItemId);
    try {
      await ref
          .read(claimsRepositoryProvider)
          .fileClaim(itemId: args.foundItemId, verificationAnswer: answer);
      if (!context.mounted) return;
      ref.invalidate(chatLifecycleProvider(lifecycleParams));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyDatabaseError(
              e,
              // The database's own explanations (too short, same answer, no
              // attempts left, wait) are shown as they are; anything else —
              // typically the post no longer being open for claims — gets this.
              fallback: "Couldn't submit the claim. The post may no longer be open "
                  'for claims — pull to refresh and try again.',
            ),
          ),
        ),
      );
      ref.invalidate(chatLifecycleProvider(lifecycleParams));
    } finally {
      _filing.remove(args.foundItemId);
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
    } else if (claim == null && !_postOpenForClaims) {
      // Someone else's claim was approved, or the post expired: the database
      // refuses a new claim, so don't offer one.
      message = args.iAmClaimant
          ? (status.itemStatus == 'expired'
              ? 'This post has expired, so it can no longer be claimed.'
              : 'This post is no longer open for claims.')
          : 'This post is no longer open for claims.';
    } else if (claim == null) {
      if (args.iAmClaimant) {
        message = 'Think this is yours? File a claim to verify it.'
            '${status.attempts != null ? '\n${claimAttemptsIntro(status.attempts!)}' : ''}';
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
        final expected = ref.watch(proofAnswerProvider(args.foundItemId)).value;
        final standing = ref.watch(personStandingProvider(args.otherUserId)).value;
        message = 'Claim: "${claim.verificationAnswer}"'
            '${standing != null ? '\nClaimant: ${standing.describe()}' : ''}'
            '${(expected != null && expected.trim().isNotEmpty) ? '\nYour expected answer: "${expected.trim()}"' : ''}';
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
      final attempts = status.attempts;
      if (args.iAmClaimant && attempts != null) {
        // Warn BEFORE the limit (attempts and any wait left) and say so plainly
        // AT it — no button once the attempts are used up.
        message = claimRejectedMessage(attempts);
        if (!attempts.isLocked && _postOpenForClaims) {
          action = OutlinedButton(
            // Always tappable: _fileClaim re-checks the standing and explains a wait
            // that has just started or just ended, so a stale banner can't strand anyone.
            onPressed: () => _fileClaim(context, ref),
            child: const Text('File a new claim'),
          );
        }
      } else {
        message = "That claim wasn't approved.";
        if (args.iAmClaimant && _postOpenForClaims) {
          action = OutlinedButton(
            onPressed: () => _fileClaim(context, ref),
            child: const Text('File a new claim'),
          );
        }
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

/// Content of the "How did it go?" rating dialog — same reasoning as
/// [ClaimAnswerDialog] for why this owns its controller as a proper
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
            maxLength: 500,
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
