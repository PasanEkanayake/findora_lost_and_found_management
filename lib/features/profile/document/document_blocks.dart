import 'package:flutter/material.dart';

/// Tiny content model for the in-app documents (user manual, safety
/// guidelines, privacy policy). Content lives in `document_content.dart`;
/// this file is only the vocabulary it's written in and the renderer.
sealed class DocBlock {
  const DocBlock();
}

final class DocHeading extends DocBlock {
  const DocHeading(this.text);
  final String text;
}

/// Body text. `**double asterisks**` render bold.
final class DocParagraph extends DocBlock {
  const DocParagraph(this.text);
  final String text;
}

final class DocBullets extends DocBlock {
  const DocBullets(this.items);
  final List<String> items;
}

/// Numbered steps.
final class DocSteps extends DocBlock {
  const DocSteps(this.items);
  final List<String> items;
}

enum DocCalloutKind { tip, warning, info }

final class DocCallout extends DocBlock {
  const DocCallout(this.kind, this.text);
  final DocCalloutKind kind;
  final String text;
}

class DocSection {
  const DocSection({required this.title, required this.blocks, this.icon});
  final String title;
  final IconData? icon;
  final List<DocBlock> blocks;
}

/// Turns `**bold**` markers into styled spans. Text with an unmatched marker
/// is shown literally rather than half-styled or dropped.
InlineSpan richSpan(String text, TextStyle? base) {
  final parts = text.split('**');
  // An even number of parts means an odd number of markers: unmatched.
  if (parts.length.isEven) return TextSpan(text: text, style: base);
  return TextSpan(
    style: base,
    children: [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          TextSpan(
            text: parts[i],
            style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
    ],
  );
}

/// Renders a list of [DocBlock]s. Text scales with the system font size —
/// nothing here has a fixed height.
class DocBlocksView extends StatelessWidget {
  const DocBlocksView({super.key, required this.blocks});

  final List<DocBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final block in blocks) _buildBlock(context, block)],
    );
  }

  Widget _buildBlock(BuildContext context, DocBlock block) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.5);

    switch (block) {
      case DocHeading(:final text):
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Semantics(
            header: true,
            child: Text(text, style: theme.textTheme.titleSmall),
          ),
        );
      case DocParagraph(:final text):
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(richSpan(text, body)),
        );
      case DocBullets(:final items):
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, right: 10, left: 2),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(child: Text.rich(richSpan(item, body))),
                    ],
                  ),
                ),
            ],
          ),
        );
      case DocSteps(:final items):
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text.rich(richSpan(items[i], body)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case DocCallout(:final kind, :final text):
        final (IconData icon, Color color, String label) = switch (kind) {
          DocCalloutKind.tip => (Icons.lightbulb_outline, theme.colorScheme.tertiary, 'Tip'),
          DocCalloutKind.warning => (
              Icons.warning_amber_rounded,
              theme.colorScheme.error,
              'Important',
            ),
          DocCalloutKind.info => (Icons.info_outline, theme.colorScheme.primary, 'Note'),
        };
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Semantics(
            container: true,
            label: label,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                // Uniform on purpose: Flutter asserts if a borderRadius is
                // combined with a border whose sides differ.
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 10),
                  Expanded(child: Text.rich(richSpan(text, body))),
                ],
              ),
            ),
          ),
        );
    }
  }
}
