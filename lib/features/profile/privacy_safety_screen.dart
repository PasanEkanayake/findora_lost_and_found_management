import 'package:flutter/material.dart';

/// Static content, but genuinely useful content — not a placeholder.
/// Meetup safety guidance is one of the most concrete things a lost &
/// found app can offer, since the whole point of the app is arranging
/// in-person handoffs with strangers.
class PrivacySafetyScreen extends StatelessWidget {
  const PrivacySafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & safety')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(icon: Icons.handshake_outlined, title: 'Meeting up safely'),
          const _TipTile(
            text: 'Meet in a public place — a café, a mall entrance, a police '
                'station lobby — never a private address.',
          ),
          const _TipTile(
            text: 'Bring a friend if you can, and let someone know where '
                "you're going and who you're meeting.",
          ),
          const _TipTile(
            text: "Trust the claim process: don't hand over an item until "
                "you've approved a claim with a verification answer that "
                "actually convinces you.",
          ),
          const _TipTile(
            text: 'For anything valuable, consider meeting during daylight '
                'hours in a busy, well-lit location.',
          ),
          const SizedBox(height: 28),
          _SectionHeader(icon: Icons.shield_outlined, title: 'What we share'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              "Your exact address is never shown to other users — only the "
              "general location label you choose when posting. Your email "
              "and phone number are never shown to another user unless you "
              "choose to share them directly in chat. Photos and item "
              "descriptions you post are visible to everyone browsing the app, "
              "since that's what makes matching possible.",
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
            ),
          ),
          const SizedBox(height: 28),
          _SectionHeader(icon: Icons.flag_outlined, title: 'Reporting a problem'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'If an item listing looks like spam, a scam, or otherwise '
              'doesn\'t belong, open it and tap the flag icon in the top '
              'right to report it to a moderator.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          Text(title, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _TipTile extends StatelessWidget {
  const _TipTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: theme.colorScheme.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
