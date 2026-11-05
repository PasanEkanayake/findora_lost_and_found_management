/// What a claim's answer has to look like before it can be submitted — the
/// same rules the database enforces (supabase/39_claim_answer_rules.sql), shown
/// here so the person is told BEFORE tapping Submit rather than after.
const int kClaimMinLengthWithQuestion = 2;
const int kClaimMinLengthWithoutQuestion = 15;
const int kClaimMaxLength = 500;

int claimMinLength({required bool hasQuestion}) =>
    hasQuestion ? kClaimMinLengthWithQuestion : kClaimMinLengthWithoutQuestion;

String _normalise(String text) => text.trim().toLowerCase();

/// Why [raw] can't be submitted yet, in words fit to show; null when it can.
///
/// [hasQuestion]: the finder set a question (short answers are fine).
/// [previousAnswer]: the answer this person already submitted for this post, so
/// the same words aren't sent twice — a rejected answer won't be accepted on a
/// second try and each try is one of a limited number.
String? validateClaimAnswer(
  String raw, {
  required bool hasQuestion,
  String? previousAnswer,
}) {
  final answer = raw.trim();
  final min = claimMinLength(hasQuestion: hasQuestion);

  if (answer.isEmpty) {
    return hasQuestion
        ? "Answer the finder's question to continue."
        : 'Describe a unique detail that proves this is yours.';
  }
  if (answer.length < min) {
    return hasQuestion
        ? 'Add a little more to your answer.'
        : 'Add more detail — at least $min characters (${answer.length} so far).';
  }
  if (previousAnswer != null &&
      previousAnswer.trim().isNotEmpty &&
      _normalise(previousAnswer) == _normalise(answer)) {
    return 'You already tried that answer. Add more detail, or try a different one.';
  }
  return null;
}
