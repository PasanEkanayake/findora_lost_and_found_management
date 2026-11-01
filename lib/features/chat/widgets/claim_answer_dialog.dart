import 'package:flutter/material.dart';

import '../../items/data/claim_answer_rules.dart';
import '../../items/data/claim_attempt_status.dart';
import '../../items/widgets/claim_attempt_notice.dart';

/// Opens the "File a claim" form. Returns the trimmed answer, or null if the
/// person cancelled.
///
/// Can't be dismissed by tapping outside it: a stray tap used to throw away a
/// carefully written answer (and, since the attempts are limited, people need
/// to get it right).
Future<String?> showClaimAnswerDialog(
  BuildContext context, {
  String? question,
  ClaimAttemptStatus? attempts,
  String? previousAnswer,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ClaimAnswerDialog(
      question: question,
      attempts: attempts,
      previousAnswer: previousAnswer,
    ),
  );
}

/// Content of the "File a claim" dialog, as its own widget so its
/// [TextEditingController] is disposed with the dialog.
///
/// Submit stays disabled until the answer follows the rules
/// ([validateClaimAnswer]); what's missing is explained under the box once the
/// person has started typing. Before this, Submit was always enabled and an
/// empty answer just closed the form — nothing was sent and nothing was said.
class ClaimAnswerDialog extends StatefulWidget {
  const ClaimAnswerDialog({super.key, this.question, this.attempts, this.previousAnswer});

  /// The finder's proof question, if they set one.
  final String? question;

  /// Which attempt this is and what's left (null if the database doesn't say).
  final ClaimAttemptStatus? attempts;

  /// The answer this person already submitted for this post, if any.
  final String? previousAnswer;

  @override
  State<ClaimAnswerDialog> createState() => _ClaimAnswerDialogState();
}

class _ClaimAnswerDialogState extends State<ClaimAnswerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasQuestion => widget.question != null && widget.question!.trim().isNotEmpty;

  String? get _problem => validateClaimAnswer(
        _controller.text,
        hasQuestion: _hasQuestion,
        previousAnswer: widget.previousAnswer,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = widget.attempts == null ? null : claimDialogWarning(widget.attempts!);
    final problem = _problem;
    final typedSomething = _controller.text.trim().isNotEmpty;
    final min = claimMinLength(hasQuestion: _hasQuestion);

    return AlertDialog(
      title: const Text('File a claim'),
      // Scrolls, so a long question + the attempt warning + the keyboard never
      // push the buttons off a small screen.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warning != null) ...[
              ClaimAttemptNotice(message: warning, urgent: widget.attempts!.isLastAttempt),
              const SizedBox(height: 12),
            ],
            if (_hasQuestion) ...[
              Text('The finder asks:', style: theme.textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(
                widget.question!.trim(),
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              maxLength: kClaimMaxLength,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _hasQuestion
                    ? 'Your answer'
                    : 'Describe a unique detail that proves this is yours',
                // Guidance until they start typing; the specific problem after.
                helperText: _hasQuestion
                    ? null
                    : 'Something only the owner would know — a mark, what was inside, '
                        'a serial number. At least $min characters.',
                helperMaxLines: 3,
                errorText: typedSomething ? problem : null,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: problem == null ? () => Navigator.pop(context, _controller.text.trim()) : null,
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
