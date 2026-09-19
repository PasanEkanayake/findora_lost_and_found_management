import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/supabase_client.dart';
import 'data/contact_message_model.dart';
import 'data/contact_providers.dart';

/// Everything ContactChatScreen needs, passed via go_router's `extra`.
class ContactChatArgs {
  const ContactChatArgs({
    required this.threadId,
    required this.itemTitle,
    required this.otherUserName,
  });

  final String threadId;
  final String itemTitle;
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

  @override
  void initState() {
    super.initState();
    ref.read(contactRepositoryProvider).markThreadRead(widget.args.threadId);
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
      await ref
          .read(contactRepositoryProvider)
          .sendMessage(threadId: widget.args.threadId, content: text);
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
    final messagesAsync = ref.watch(contactMessagesStreamProvider(widget.args.threadId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args.otherUserName),
        // Reminds either side what this thread is actually about — unlike
        // ChatScreen, where the item is implied by the confirmed match.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'About "${widget.args.itemTitle}"',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
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
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final isMine = message.senderId == myId;
                    return _ContactMessageBubble(message: message, isMine: isMine);
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

class _ContactMessageBubble extends StatelessWidget {
  const _ContactMessageBubble({required this.message, required this.isMine});

  final ContactMessageModel message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor =
        isMine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
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
              style:
                  theme.textTheme.labelSmall?.copyWith(color: textColor.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
