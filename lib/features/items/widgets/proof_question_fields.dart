import 'package:flutter/material.dart';

/// The optional "proof question" section of the post/edit form for a FOUND
/// item: a question only the real owner could answer, and — privately — the
/// right answer. The question is shown to whoever files a claim; the answer is
/// stored in an owner-only table and shown only to the finder, next to the
/// claimant's answer, when deciding (supabase/24_proof_questions.sql).
class ProofQuestionFields extends StatelessWidget {
  const ProofQuestionFields({
    super.key,
    required this.questionController,
    required this.answerController,
  });

  final TextEditingController questionController;
  final TextEditingController answerController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Proof question (optional)', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ask something only the real owner could answer, so you can tell them '
            "apart from someone who just says it's theirs. Don't put the answer in "
            'the question — and only you will ever see your answer.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: questionController,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Question',
              hintText: 'e.g. What is on the lock screen?',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: answerController,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Right answer (only you can see this)',
            ),
          ),
        ],
      ),
    );
  }
}
