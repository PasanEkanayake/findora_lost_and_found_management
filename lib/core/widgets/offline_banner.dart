import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../connectivity/connectivity_provider.dart';

/// Wraps the whole app (see `MaterialApp.router(builder:)` in main.dart) and
/// slides a slim banner in at the top while the backend can't be reached:
/// "You're offline — showing what's already loaded". When the connection
/// comes back it turns green for two seconds ("Back online") and goes away.
///
/// The banner sits ABOVE the app's screens (not over them), so it never
/// covers an app bar or a button. It takes over the status-bar inset while
/// it is showing, and the screens below are told that inset is gone so
/// their own app bars don't pad for it a second time.
class OfflineBannerHost extends ConsumerStatefulWidget {
  const OfflineBannerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OfflineBannerHost> createState() => _OfflineBannerHostState();
}

class _OfflineBannerHostState extends ConsumerState<OfflineBannerHost> {
  bool _backOnline = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onChanged(bool? wasOnline, bool isOnline) {
    if (wasOnline == false && isOnline) {
      setState(() => _backOnline = true);
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _backOnline = false);
      });
    } else if (!isOnline) {
      _hideTimer?.cancel();
      if (_backOnline) setState(() => _backOnline = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(connectivityProvider, (previous, next) => _onChanged(previous, next));
    final online = ref.watch(connectivityProvider);
    final showBanner = !online || _backOnline;
    final topInset = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: showBanner
              ? _Banner(online: online, topInset: topInset)
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          // Always the same widget (only the flag changes) so the app's
          // screens keep their state when the banner comes and goes.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: showBanner,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.online, required this.topInset});

  final bool online;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = online ? Colors.green.shade700 : theme.colorScheme.inverseSurface;
    final foreground = online ? Colors.white : theme.colorScheme.onInverseSurface;

    return Semantics(
      liveRegion: true,
      child: Material(
        color: background,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  size: 18, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  online
                      ? AppLocalizations.of(context).backOnline
                      : AppLocalizations.of(context).offlineBanner,
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
