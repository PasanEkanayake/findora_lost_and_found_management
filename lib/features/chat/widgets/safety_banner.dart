import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A short, dismissible reminder at the top of a conversation. Shown until
/// the person closes it once; after that it stays away (the full guidance is
/// always under Profile → Safety guidelines).
class SafetyBanner extends StatefulWidget {
  const SafetyBanner({super.key});

  static const _prefsKey = 'chat_safety_banner_dismissed';

  @override
  State<SafetyBanner> createState() => _SafetyBannerState();
}

class _SafetyBannerState extends State<SafetyBanner> {
  bool _visible = false; // hidden until we know it hasn't been dismissed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _visible = !(prefs.getBool(SafetyBanner._prefsKey) ?? false));
    } catch (_) {
      // Preferences unavailable: showing the reminder is the safe default.
      if (mounted) setState(() => _visible = true);
    }
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SafetyBanner._prefsKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 18, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Stay safe: meet somewhere public, never send money or codes, '
                        "and check it's really yours before handing anything over. ",
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () => context.push('/profile/safety'),
                      child: Text(
                        'Safety tips',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            icon: Icon(Icons.close, size: 18, color: theme.colorScheme.onTertiaryContainer),
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }
}
