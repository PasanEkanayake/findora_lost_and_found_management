import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A shimmering placeholder list matching the app's common "leading image
/// + title + subtitle" card shape (item feed, matches, my items) — shown
/// while real data loads, instead of a bare spinner that gives no sense
/// of what's about to appear.
class ShimmerCardList extends StatelessWidget {
  const ShimmerCardList({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(16),
  });

  final int itemCount;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final block = _blockColor(theme);

    return Shimmer.fromColors(
      baseColor: theme.colorScheme.surfaceContainerHighest,
      highlightColor: theme.colorScheme.surface,
      child: ListView.separated(
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(12)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 70, height: 12, color: block),
                      const SizedBox(height: 8),
                      Container(width: double.infinity, height: 14, color: block),
                      const SizedBox(height: 8),
                      Container(width: 130, height: 10, color: block),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _blockColor(ThemeData theme) =>
      theme.brightness == Brightness.dark ? Colors.white24 : Colors.white;
}

/// A shimmering placeholder list matching a circular-avatar row (chat
/// list) — shown while conversations load.
class ShimmerTileList extends StatelessWidget {
  const ShimmerTileList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final block = theme.brightness == Brightness.dark ? Colors.white24 : Colors.white;

    return Shimmer.fromColors(
      baseColor: theme.colorScheme.surfaceContainerHighest,
      highlightColor: theme.colorScheme.surface,
      child: ListView.separated(
        itemCount: itemCount,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(radius: 26, backgroundColor: block),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 120, height: 14, color: block),
                    const SizedBox(height: 8),
                    Container(width: 190, height: 10, color: block),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
