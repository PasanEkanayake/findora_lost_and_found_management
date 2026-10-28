import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The row under a paged list: a "Show more" button, or a small spinner while
/// the next rows are loading.
class ShowMoreButton extends StatelessWidget {
  const ShowMoreButton({super.key, required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: loading
            ? const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : OutlinedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.expand_more),
                label: Text(AppLocalizations.of(context).commonShowMore),
              ),
      ),
    );
  }
}
