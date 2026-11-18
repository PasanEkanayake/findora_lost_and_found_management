import 'package:flutter/material.dart';

/// Asks for a short note before a moderation action, shown to the post's owner
/// and kept in the audit log.
///
/// Returns the note ('' when optional and left empty), or null if cancelled.
Future<String?> showModerationNoteDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String hint = 'Note for the owner (optional)',
  bool noteRequired = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NoteDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      hint: hint,
      noteRequired: noteRequired,
    ),
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.hint,
    required this.noteRequired,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String hint;
  final bool noteRequired;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => !widget.noteRequired || _controller.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: widget.hint),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? () => Navigator.pop(context, _controller.text.trim()) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
