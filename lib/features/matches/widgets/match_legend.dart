import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/match_model.dart';

/// What each match label means, in one place — used by the card at the top of
/// the Matches list and by the ⓘ button in its app bar.
class _TierInfo {
  const _TierInfo(this.tier, this.range, this.meaning);

  final MatchTier tier;
  final String range;
  final String meaning;
}

String _percent(double fraction) => '${(fraction * 100).round()}%';

final List<_TierInfo> _tiers = [
  _TierInfo(
    MatchTier.strong,
    '${_percent(MatchTier.strongFrom)} and up',
    'The photos look alike and the wording, place and time also fit. Very likely the '
        'same item — still check the details before handing anything over.',
  ),
  _TierInfo(
    MatchTier.likely,
    '${_percent(MatchTier.likelyFrom)} to ${_percent(MatchTier.strongFrom)}',
    'Several things line up, but something is missing or weaker — for example there is no '
        'photo to compare. Worth a close look.',
  ),
  _TierInfo(
    MatchTier.possible,
    'below ${_percent(MatchTier.likelyFrom)}',
    'Only weak evidence: maybe similar wording or a nearby place, or the photos look '
        'different. Check carefully before replying.',
  ),
];

const String _footnote =
    'The percentage shows how much of the evidence agrees — it is not the chance of being '
    'right. Photos that look different pull a match down, and matches are only made between '
    'posts in the same country.';

Color _tierColor(ThemeData theme, MatchTier tier) => switch (tier) {
      MatchTier.strong => theme.colorScheme.primary,
      MatchTier.likely => theme.colorScheme.tertiary,
      MatchTier.possible => theme.colorScheme.onSurfaceVariant,
    };

class _TierRow extends StatelessWidget {
  const _TierRow({required this.info});

  final _TierInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _tierColor(theme, info.tier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5, right: 10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${info.tier.label} match',
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                  TextSpan(
                    text: '  ${info.range}\n',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  TextSpan(text: info.meaning, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ⓘ button's sheet.
Future<void> showMatchLegendSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What the match labels mean', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final info in _tiers) _TierRow(info: info),
            const SizedBox(height: 4),
            Text(
              _footnote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A short summary card at the top of the Matches list, until it is dismissed
/// ("Got it"). The ⓘ button in the app bar always brings the same text back.
class MatchLegendCard extends StatefulWidget {
  const MatchLegendCard({super.key});

  static const _prefsKey = 'match_legend_dismissed';

  @override
  State<MatchLegendCard> createState() => _MatchLegendCardState();
}

class _MatchLegendCardState extends State<MatchLegendCard> {
  bool _visible = false; // hidden until we know it hasn't been dismissed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _visible = !(prefs.getBool(MatchLegendCard._prefsKey) ?? false));
      }
    } catch (_) {
      if (mounted) setState(() => _visible = true);
    }
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(MatchLegendCard._prefsKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('How to read these matches', style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final info in _tiers) _TierRow(info: info),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _dismiss, child: const Text('Got it')),
            ),
          ],
        ),
      ),
    );
  }
}
