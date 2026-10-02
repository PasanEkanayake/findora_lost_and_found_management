import 'package:flutter/material.dart';

import 'document_blocks.dart';

/// A long-form document read top to bottom — used for the privacy policy
/// and safety guidelines. Every section is open (unlike the user manual's
/// collapsible sections): a policy shouldn't hide parts of itself behind a tap.
class DocumentScreen extends StatelessWidget {
  const DocumentScreen({
    super.key,
    required this.title,
    required this.sections,
    this.intro,
    this.footer,
  });

  final String title;
  final List<DocSection> sections;

  /// Shown above the first section (e.g. "Last updated …").
  final String? intro;

  /// Shown after the last section.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (intro != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                intro!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          for (final section in sections) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (section.icon != null) ...[
                  Icon(section.icon, color: theme.colorScheme.primary, size: 22),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(section.title, style: theme.textTheme.titleMedium),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DocBlocksView(blocks: section.blocks),
          ],
          if (footer != null) ...[const SizedBox(height: 24), footer!],
        ],
      ),
    );
  }
}
