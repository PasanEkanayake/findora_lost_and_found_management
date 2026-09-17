import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _faqs = [
    (
      'How does the AI matching work?',
      "When you post a photo, an on-device model analyzes it and compares "
          "it against opposite-type items (lost vs. found) in the same "
          "category. Strong matches show up in the Matches tab automatically.",
    ),
    (
      "I found a match, now what?",
      'Confirm it from the Matches tab, then message the other person to '
          'arrange verification. Once they file a claim and you approve it, '
          "you'll get a \"Mark as returned\" button once the handoff happens.",
    ),
    (
      "Why do I need to verify a claim before sharing contact info?",
      "It protects both sides — the finder can confirm the claimant really "
          "owns the item before arranging a meetup, without needing to share "
          "personal details up front.",
    ),
    (
      'How do I delete an item I posted?',
      "Open the item from your profile's \"My reported items\" list. "
          "In-app deletion is on the roadmap — for now, reach out to support "
          "below and we'll remove it for you.",
    ),
  ];

  Future<void> _contactSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@findora.app',
      query: 'subject=${Uri.encodeComponent('Findora support request')}',
    );
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email app found — reach us at support@findora.app'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Frequently asked questions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final faq in _faqs)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(faq.$1, style: theme.textTheme.titleSmall),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  faq.$2,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          const Divider(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Still need help?", style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    "Send us an email and we'll get back to you as soon as we can.",
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _contactSupport(context),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('Contact support'),
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
