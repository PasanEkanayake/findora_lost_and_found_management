import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/post_link_bar.dart';
import '../chat/data/messages_repository.dart' show kChatPageSize;
import '../chat/data/chat_images.dart';
import '../chat/data/typing_channel.dart';
import '../chat/widgets/chat_bubble.dart';
import '../chat/widgets/chat_composer.dart';
import '../chat/widgets/chat_safety_menu.dart';
import '../chat/widgets/typing_indicator.dart';
import '../items/widgets/photo_strip.dart' show pickPhotoWithSheet;
import '../chat/widgets/load_earlier_button.dart';
import '../chat/widgets/safe_send.dart';
import '../chat/widgets/safety_banner.dart';
import 'data/contact_providers.dart';

/// Everything ContactChatScreen needs, passed via go_router's `extra`.
class ContactChatArgs {
  const ContactChatArgs({
    required this.threadId,
    required this.itemId,
    required this.itemTitle,
    required this.otherUserId,
    required this.otherUserName,
  });

  final String threadId;

  /// The post this thread is about — lets the chat link straight to it.
  final String itemId;
  final String itemTitle;
  final String otherUserId;
  final String otherUserName;
}

/// A plain messaging thread about one item — no claim/rating lifecycle
/// attached (that stays exclusive to ChatScreen, reached only through a
/// confirmed AI match). This exists for the lighter "quick question before
/// I'm sure it's mine" case; see supabase/06_contact_messaging.sql's header
/// comment for the full reasoning.
class ContactChatScreen extends ConsumerStatefulWidget {
  const ContactChatScreen({super.key, required this.args});

  final ContactChatArgs args;

  @override
  ConsumerState<ContactChatScreen> createState() => _ContactChatScreenState();
}

class _ContactChatScreenState extends ConsumerState<ContactChatScreen> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  late final TypingChannel _typing;
  bool _sendingPhoto = false;
  Timer? _syncTimer;
  String? _lastMarkedReadId;
  bool _noMoreEarlier = false; // set once "Load earlier" runs out of messages

  @override
  void initState() {
    super.initState();
    _typing = TypingChannel(
      topic: 'typing:c:${widget.args.threadId}',
      myId: supabase.auth.currentUser?.id ?? '',
    )..start();
    final repo = ref.read(contactRepositoryProvider);
    repo.markThreadRead(widget.args.threadId);
    // The message provider stays alive between visits (see
    // contactMessagesStreamProvider), so anything sent while this screen
    // was closed is pulled in straight away instead of after the first tick.
    repo.syncNow(widget.args.threadId);
    // Safety net for the realtime channel — see ContactRepository.syncNow.
    _syncTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => repo.syncNow(widget.args.threadId),
    );
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
      await ref
          .read(contactRepositoryProvider)
          .sendMessage(threadId: widget.args.threadId, content: text);
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
        kind: ChatKind.thread,
        conversationId: widget.args.threadId,
        file: file,
      );
      await ref.read(contactRepositoryProvider).sendMessage(
            threadId: widget.args.threadId,
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
    final messagesAsync = ref.watch(contactMessagesStreamProvider(widget.args.threadId));

    // A message that arrives while this screen is open is read the moment
    // it appears — without this it would stay "unread" (and show a badge
    // in the Chats list) until the thread was next reopened.
    ref.listen(contactMessagesStreamProvider(widget.args.threadId), (previous, next) {
      final messages = next.value;
      if (messages == null || messages.isEmpty) return;
      final latest = messages.last;
      if (latest.senderId != myId && latest.id != _lastMarkedReadId) {
        _lastMarkedReadId = latest.id;
        _typing.otherSentMessage();
        ref.read(contactRepositoryProvider).markThreadRead(widget.args.threadId);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args.otherUserName),
        actions: [
          ChatSafetyMenu(
            onSuggestMeetup: () {
              _controller.text = kSafeMeetupMessage;
              _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
            },
            otherUserId: widget.args.otherUserId,
            otherUserLabel: widget.args.otherUserName,
            threadId: widget.args.threadId,
          ),
        ],
      ),
      body: Column(
        children: [
          // What this thread is about — replaces the old "About ..." caption
          // under the title, and opens the post when tapped.
          PostLinkBar(
            posts: [
              ChatPostLink(
                caption: 'ABOUT THIS POST',
                itemId: widget.args.itemId,
                fallbackTitle: widget.args.itemTitle,
              ),
            ],
          ),
          const SafetyBanner(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "This is a general question thread — for handing something back, "
                    'use the AI match flow so ownership gets verified first.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
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
                      'Say hello — ask your question about this item.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                }
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
                              .read(contactRepositoryProvider)
                              .loadEarlierMessages(widget.args.threadId, messages.first.createdAt);
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
