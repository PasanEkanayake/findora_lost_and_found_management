import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/chat_images.dart';

/// One message in either kind of chat: an optional photo, an optional text,
/// and the time. Replaces the two near-identical private bubbles the two chat
/// screens used to have.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.isMine,
    required this.content,
    required this.createdAt,
    this.imagePath,
  });

  final bool isMine;

  /// The text — or the caption under a photo; empty for a photo on its own.
  final String content;
  final DateTime createdAt;

  /// Path of the photo in the private chat bucket, if the message has one.
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor =
        isMine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final path = imagePath;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        // A photo gets a slim frame of bubble colour; text keeps its padding.
        padding: path != null
            ? const EdgeInsets.fromLTRB(4, 4, 4, 8)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            if (path != null) ChatPhoto(path: path),
            if (content.isNotEmpty)
              Padding(
                padding: path != null
                    ? const EdgeInsets.fromLTRB(10, 8, 10, 0)
                    : EdgeInsets.zero,
                child: Text(
                  content,
                  style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(
                top: 2,
                left: path != null ? 10 : 0,
                right: path != null ? 10 : 0,
              ),
              child: Text(
                DateFormat.jm().format(createdAt),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: textColor.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A photo inside a chat bubble. Loads through a signed link (the bucket is
/// private); tap to see it full screen. Shows a grey tile while loading and a
/// "tap to retry" tile if it can't be loaded.
class ChatPhoto extends ConsumerWidget {
  const ChatPhoto({super.key, required this.path});

  final String path;

  static const double _size = 220;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final urlAsync = ref.watch(chatImageUrlProvider(path));

    Widget tile(Widget child, {VoidCallback? onTap}) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        );

    return urlAsync.when(
      loading: () => tile(const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      )),
      error: (_, __) => tile(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              "Couldn't load — tap to retry",
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        onTap: () => ref.invalidate(chatImageUrlProvider(path)),
      ),
      data: (url) => Semantics(
        button: true,
        label: 'Photo in chat. Tap to view full screen.',
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => ChatPhotoViewer(path: path, url: url),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: url,
              // The signed link changes every hour; the photo doesn't. Keying
              // the cache on the path keeps it cached between visits.
              cacheKey: path,
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              // Decode near display size rather than at full resolution.
              memCacheWidth: 660,
              placeholder: (_, __) => tile(const SizedBox.shrink()),
              errorWidget: (_, __, ___) => tile(
                Icon(Icons.broken_image_outlined, color: theme.colorScheme.onSurfaceVariant),
                onTap: () => ref.invalidate(chatImageUrlProvider(path)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The photo on its own, pinch to zoom.
class ChatPhotoViewer extends StatelessWidget {
  const ChatPhotoViewer({super.key, required this.path, required this.url});

  final String path;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: CachedNetworkImage(
            imageUrl: url,
            cacheKey: path,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined,
                color: Colors.white70, size: 48),
          ),
        ),
      ),
    );
  }
}
