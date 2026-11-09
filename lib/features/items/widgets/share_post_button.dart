import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/sharing/share_links.dart';
import '../data/item_model.dart';

/// The Share icon on a post's page: sends a link to the post (never its
/// description, the poster or the location — just the title and the link)
/// through the phone's share sheet.
///
/// Takes no space when sharing isn't set up (`SHARE_BASE_URL` in `.env`) or
/// the post isn't something to share any more — only an open post has a page
/// anyone else can see. [linkBuilder] and [onShare] exist for tests.
class SharePostButton extends StatelessWidget {
  const SharePostButton({
    super.key,
    required this.item,
    this.linkBuilder = ShareLinks.postUrl,
    this.onShare = _shareViaSheet,
  });

  final ItemModel item;
  final String? Function(String itemId) linkBuilder;
  final Future<void> Function(String text, String subject) onShare;

  // share_plus 11+ API (the old static `Share.share` is deprecated/removed).
  static Future<void> _shareViaSheet(String text, String subject) =>
      SharePlus.instance.share(ShareParams(text: text, subject: subject));

  @override
  Widget build(BuildContext context) {
    if (item.status != 'open') return const SizedBox.shrink();
    final url = linkBuilder(item.id);
    if (url == null) return const SizedBox.shrink();

    return IconButton(
      icon: const Icon(Icons.share_outlined),
      tooltip: 'Share this post',
      onPressed: () async {
        final text = ShareLinks.shareText(isLost: item.isLost, title: item.title, url: url);
        final subject = '${item.isLost ? 'Lost' : 'Found'}: ${item.title}';
        final messenger = ScaffoldMessenger.of(context);
        try {
          await onShare(text, subject);
        } catch (_) {
          // No share sheet available: put the link on the clipboard instead.
          await Clipboard.setData(ClipboardData(text: url));
          messenger.showSnackBar(const SnackBar(content: Text('Link copied.')));
        }
      },
    );
  }
}
