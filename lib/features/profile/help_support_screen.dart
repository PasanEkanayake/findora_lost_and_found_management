import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'document/document_content.dart';

/// Help & support: quick links to the longer documents, FAQs grouped by
/// topic (text in `document/document_content.dart`, kHelpFaqs), and a way
/// to reach a person.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _supportEmail = 'support@findora.app';

  Future<void> _contactSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent('Findora support request')}',
    );
    var launched = false;
    try {
      launched = await launchUrl(uri);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found — reach us at $_supportEmail')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _QuickLink(
            icon: Icons.menu_book_outlined,
            title: 'User manual',
            subtitle: 'Step-by-step guide to the whole app',
            route: '/profile/manual',
          ),
          const _QuickLink(
            icon: Icons.health_and_safety_outlined,
            title: 'Safety guidelines',
            subtitle: 'Meeting up and avoiding scams',
            route: '/profile/safety',
          ),
          const _QuickLink(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy policy',
            subtitle: 'What we collect and who can see it',
            route: '/profile/privacy',
          ),
          const SizedBox(height: 12),
          Text('Frequently asked questions', style: theme.textTheme.titleMedium),
          for (final (topic, questions) in kHelpFaqs) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Semantics(
                header: true,
                child: Text(
                  topic.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            for (final (question, answer) in questions)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(question, style: theme.textTheme.titleSmall),
                childrenPadding: const EdgeInsets.only(bottom: 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    answer,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
          ],
          const Divider(height: 40),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Still need help?', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    "Email us and we'll get back to you as soon as we can. Tell us "
                    'what you were doing and what you expected to happen — a '
                    'screenshot helps.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _contactSupport(context),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('Contact support'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _supportEmail,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(route),
      ),
    );
  }
}
