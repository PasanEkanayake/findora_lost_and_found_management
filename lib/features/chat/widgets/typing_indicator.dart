import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// A thin "typing…" row with three bouncing dots, shown above the message box
/// while the other person is typing. Takes no space when they aren't.
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key, required this.typing});

  /// Usually `TypingChannel.otherTyping`.
  final ValueListenable<bool> typing;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: typing,
      builder: (context, isTyping, _) {
        if (!isTyping) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Semantics(
          liveRegion: true,
          label: 'The other person is typing',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
                child: _Dots(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots({required this.color});

  final Color color;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
                child: Opacity(
                  // Each dot lights up a third of a cycle after the one before.
                  opacity: 0.3 + 0.7 * _pulse((_controller.value - i / 3) % 1.0),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 1 at the start of a dot's turn, fading to 0 by the end of it.
  double _pulse(double t) => t < 0.5 ? 1 - t * 2 : 0;
}
