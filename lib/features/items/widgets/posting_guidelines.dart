import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hiddenKey = 'posting_guidelines_hidden';

/// Shows the "how to fill in this form" guidance before someone starts a post.
///
/// Why it exists: a post is public, and the only protection against fake
/// claims is that the real owner knows something the post never says. This
/// asks people to keep one such detail back. Unless [force] is true (the
/// "Posting tips" link) it is skipped once the person has ticked "Don't show
/// this again".
Future<void> showPostingGuidelines(BuildContext context, {bool force = false}) async {
  if (!force) {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_hiddenKey) ?? false) return;
    } catch (_) {
      // Preferences unavailable: showing the guidance is the safe default.
    }
  }
  if (!context.mounted) return;

  // A dialog rather than a bottom sheet: the sheet configuration used before
  // (a drag handle on a sheet that can't be dragged) is not a valid combination
  // and left just the dimmed background on screen.
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _GuidelinesDialog(),
  );
}

class _GuidelinesDialog extends StatefulWidget {
  const _GuidelinesDialog();

  @override
  State<_GuidelinesDialog> createState() => _GuidelinesDialogState();
}

class _GuidelinesDialogState extends State<_GuidelinesDialog> {
  bool _dontShowAgain = false;

  Future<void> _close() async {
    if (_dontShowAgain) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_hiddenKey, true);
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget tip(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return AlertDialog(
      scrollable: true,
      title: const Text('Before you post: keep it private to the owner'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Posts are public. Share enough for the right person to recognise the '
            'item, but keep back one detail only the real owner would know — that is '
            'how fake claims get filtered out.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          tip(
            Icons.short_text,
            'Describe it in general terms',
            '"Black wallet" or "silver phone, cracked corner" is enough. Leave out '
            'serial or IMEI numbers, names, ID or card numbers, the lock-screen '
            'wallpaper and what is inside.',
          ),
          tip(
            Icons.photo_camera_outlined,
            'Show the outside only',
            "Cover or crop anything that identifies it — a name on a card or ID, a "
            "serial number, what's on a screen. Don't photograph the contents of a "
            'wallet or bag.',
          ),
          tip(
            Icons.verified_user_outlined,
            'Found something? Add a proof question',
            'Ask something only the owner could answer ("What is on the lock '
            'screen?"). Only you will ever see the right answer.',
          ),
          tip(
            Icons.search,
            'Lost something? Keep the secret detail to yourself',
            "Don't put it in your post — you'll be asked to prove it if someone "
            'finds your item.',
          ),
          tip(
            Icons.public,
            'Choose the country and the place',
            'Posts are only shown to people in the same country. Mark where it was '
            'lost or found — not your home.',
          ),
          tip(
            Icons.lock_outline,
            'Keep contact details out of the post',
            'No phone number or address in the title or description. Use the '
            'in-app chat, and share personal details only once you trust the person.',
          ),
          CheckboxListTile(
            value: _dontShowAgain,
            onChanged: (value) => setState(() => _dontShowAgain = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text("Don't show this again"),
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: _close, child: const Text('Got it')),
      ],
    );
  }
}
