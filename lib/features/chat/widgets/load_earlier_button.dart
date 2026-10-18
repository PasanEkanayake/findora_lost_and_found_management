import 'package:flutter/material.dart';

/// The row at the very top of a conversation that fetches the page of
/// messages before the ones shown. [onLoad] returns true if there may be
/// more still (the caller hides this row once it returns false).
class LoadEarlierButton extends StatefulWidget {
  const LoadEarlierButton({super.key, required this.onLoad});

  final Future<bool> Function() onLoad;

  @override
  State<LoadEarlierButton> createState() => _LoadEarlierButtonState();
}

class _LoadEarlierButtonState extends State<LoadEarlierButton> {
  bool _loading = false;
  bool _failed = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await widget.onLoad();
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: _loading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : TextButton.icon(
                onPressed: _load,
                icon: Icon(_failed ? Icons.refresh : Icons.expand_less),
                label: Text(_failed ? "Couldn't load — tap to retry" : 'Load earlier messages'),
              ),
      ),
    );
  }
}
