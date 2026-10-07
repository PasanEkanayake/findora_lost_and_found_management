import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/items/data/items_providers.dart';
import 'item_photo.dart';

/// One post a chat can link out to: which one it is ([caption], e.g.
/// "YOUR POST"), its id, and a title to show until the real one loads.
class ChatPostLink {
  const ChatPostLink({
    required this.caption,
    required this.itemId,
    required this.fallbackTitle,
  });

  final String caption;
  final String itemId;
  final String fallbackTitle;
}

/// A slim row of tappable post tiles for the top of a chat screen — one tile
/// per entry in [posts], sharing the width equally. Each shows the post's
/// photo, which post it is, and its title; tapping opens that post.
///
/// Sized to be easy to see and hit (48 dp tall, thumbnail + two text lines)
/// while costing the message list only ~60 dp. It also hides itself while
/// the keyboard is open, since that is exactly when vertical space is
/// scarcest and the person is typing rather than browsing.
class PostLinkBar extends StatelessWidget {
  const PostLinkBar({super.key, required this.posts});

  final List<ChatPostLink> posts;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final theme = Theme.of(context);

    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.topCenter,
      child: keyboardOpen
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < posts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: _PostLinkTile(link: posts[i])),
                  ],
                ],
              ),
            ),
    );
  }
}

class _PostLinkTile extends ConsumerWidget {
  const _PostLinkTile({required this.link});

  final ChatPostLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Cosmetic only: if the post can't be loaded (deleted, offline) the tile
    // still renders with the fallback title, and tapping it shows the post
    // screen's own error state with a retry button.
    final item = ref.watch(itemDetailProvider(link.itemId)).value;
    final title = item?.title ?? link.fallbackTitle;
    final caption = item == null
        ? link.caption
        : '${link.caption} · ${item.isLost ? 'LOST' : 'FOUND'}';

    return Semantics(
      button: true,
      label: '${link.caption}: $title. Opens the post.',
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/item/${link.itemId}'),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 4, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: ItemPhoto(url: item?.imageUrls.firstOrNull),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
