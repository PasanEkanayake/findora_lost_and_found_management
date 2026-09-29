import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'document/document_blocks.dart';
import 'document/document_content.dart';

/// The complete user manual: every screen and the whole lost → found →
/// returned process. Sections collapse so the page stays scannable; the
/// first one starts open. Text: `document/document_content.dart` (kUserManual);
/// a Markdown copy lives in docs/USER_MANUAL.md.
class UserManualScreen extends StatelessWidget {
  const UserManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('User manual')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Everything you need to use Findora, from creating an account to '
              'getting an item back. Tap a section to open it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          for (var i = 0; i < kUserManual.length; i++)
            _ManualSection(
              number: i + 1,
              section: kUserManual[i],
              initiallyExpanded: i == 0,
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('More to read', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/profile/safety'),
                    icon: const Icon(Icons.health_and_safety_outlined),
                    label: const Text('Safety guidelines'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/profile/privacy'),
                    icon: const Icon(Icons.privacy_tip_outlined),
                    label: const Text('Privacy policy'),
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

class _ManualSection extends StatelessWidget {
  const _ManualSection({
    required this.number,
    required this.section,
    required this.initiallyExpanded,
  });

  final int number;
  final DocSection section;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Removes ExpansionTile's default divider lines inside a Card.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(section.icon ?? Icons.article_outlined, color: theme.colorScheme.primary),
          title: Text('$number. ${section.title}', style: theme.textTheme.titleSmall),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [DocBlocksView(blocks: section.blocks)],
        ),
      ),
    );
  }
}
