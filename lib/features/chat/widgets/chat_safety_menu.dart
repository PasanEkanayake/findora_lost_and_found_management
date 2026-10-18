import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../data/safety_providers.dart';

enum _SafetyAction { suggestMeetup, report, block }

/// Put in the message box when someone picks "Suggest a safe meeting place".
const kSafeMeetupMessage = 'Could we meet somewhere public and busy, in daylight? '
    'A police station, a shop or a bank would be ideal.';

const _reportReasons = <String>[
  'Spam or advertising',
  'Harassment or abuse',
  'Scam or fraud',
  'Inappropriate content',
  'Something else',
];

/// The "⋮" menu in a chat's app bar: report this person, or block them.
/// Pass [matchId] for a match chat or [threadId] for a direct message thread.
class ChatSafetyMenu extends ConsumerWidget {
  const ChatSafetyMenu({
    super.key,
    required this.otherUserId,
    required this.otherUserLabel,
    this.matchId,
    this.threadId,
    this.onSuggestMeetup,
  });

  /// If given, the menu offers "Suggest a safe meeting place" and calls this
  /// (the chat screen puts a ready-made message in its message box).
  final VoidCallback? onSuggestMeetup;

  final String otherUserId;

  /// How to refer to them in the dialogs ("Sam", or "this person").
  final String otherUserLabel;
  final String? matchId;
  final String? threadId;

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReportDialog(label: otherUserLabel),
    );
    if (reason == null) return;

    try {
      await ref.read(safetyRepositoryProvider).reportUser(
            reportedUserId: otherUserId,
            matchId: matchId,
            threadId: threadId,
            reason: reason,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text("Thanks — we'll look into it.")),
      );
    } on PostgrestException catch (e) {
      // 23505 = the one-open-report-per-person rule.
      messenger.showSnackBar(SnackBar(
        content: Text(
          e.code == '23505'
              ? "You've already reported this person — we're reviewing it."
              : "Couldn't send the report. Try again.",
        ),
      ));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't send the report. Try again.")),
      );
    }
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.block,
      title: 'Block $otherUserLabel?',
      message: "They won't be able to message you, and this conversation will be "
          "hidden from your lists. They aren't told. You can unblock them any "
          'time from Profile → Blocked people.',
      confirmLabel: 'Block',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    // Taken before navigating away, which disposes this screen's context.
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(safetyRepositoryProvider).block(otherUserId);
      ref.invalidate(blockedUserIdsProvider);
      ref.invalidate(blockedUsersProvider);
      router.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Blocked $otherUserLabel.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't block. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_SafetyAction>(
      tooltip: 'More options',
      onSelected: (action) => switch (action) {
        _SafetyAction.suggestMeetup => onSuggestMeetup?.call(),
        _SafetyAction.report => _report(context, ref),
        _SafetyAction.block => _block(context, ref),
      },
      itemBuilder: (_) => [
        if (onSuggestMeetup != null)
          const PopupMenuItem(
            value: _SafetyAction.suggestMeetup,
            child: ListTile(
              leading: Icon(Icons.place_outlined),
              title: Text('Suggest a safe meeting place'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: _SafetyAction.report,
          child: ListTile(
            leading: Icon(Icons.flag_outlined),
            title: Text('Report this person'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: _SafetyAction.block,
          child: ListTile(
            leading: Icon(Icons.block),
            title: Text('Block this person'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.label});

  final String label;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String? _reason;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report ${widget.label}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                children: [
                  for (final reason in _reportReasons)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(reason),
                      value: reason,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Anything else we should know? (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _reason == null
              ? null
              : () {
                  final details = _details.text.trim();
                  Navigator.pop(context, details.isEmpty ? _reason : '$_reason: $details');
                },
          child: const Text('Send report'),
        ),
      ],
    );
  }
}
