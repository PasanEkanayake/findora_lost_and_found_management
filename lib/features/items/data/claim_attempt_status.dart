/// A claimant's standing on ONE post: how many of their allowed claims are
/// used, and whether they must wait before the next. The numbers come from the
/// database (`claim_attempt_status()` in supabase/38_claim_attempt_limit.sql),
/// which also enforces them — this only decides what to SAY.
class ClaimAttemptStatus {
  const ClaimAttemptStatus({
    required this.attemptsUsed,
    required this.maxAttempts,
    this.hasLiveClaim = false,
    this.retryAt,
  });

  /// Claims filed on this post that count (rejections from before the limit
  /// existed, and any a moderator gave back, don't).
  final int attemptsUsed;
  final int maxAttempts;

  /// A claim is pending or approved — nothing more to file right now.
  final bool hasLiveClaim;

  /// When the wait after the last rejection ends; null when there's no wait.
  final DateTime? retryAt;

  int get attemptsLeft => (maxAttempts - attemptsUsed).clamp(0, maxAttempts);

  /// No attempts left: the post can't be claimed again from this account.
  bool get isLocked => attemptsLeft == 0;

  /// The next claim is the final one.
  bool get isLastAttempt => attemptsLeft == 1;

  /// Which attempt a claim filed now would be (1-based).
  int get nextAttemptNumber => attemptsUsed + 1;

  /// Whole minutes until another claim may be filed (at least 1), or null when
  /// nothing is stopping the person. [now] is for tests.
  int? waitMinutes({DateTime? now}) {
    final at = retryAt;
    if (at == null || isLocked) return null;
    final remaining = at.difference(now ?? DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) return null;
    return (remaining.inSeconds / 60).ceil().clamp(1, 1 << 30);
  }

  factory ClaimAttemptStatus.fromMap(Map<String, dynamic> map) {
    final retry = map['retry_at'] as String?;
    return ClaimAttemptStatus(
      attemptsUsed: (map['attempts_used'] as num).toInt(),
      maxAttempts: (map['max_attempts'] as num).toInt(),
      hasLiveClaim: (map['has_live_claim'] as bool?) ?? false,
      retryAt: retry == null ? null : DateTime.parse(retry).toLocal(),
    );
  }
}

String _attempts(int n) => n == 1 ? '1 attempt' : '$n attempts';
String _minutes(int n) => n == 1 ? '1 minute' : '$n minutes';

/// Shown in the chat banner before the person has filed anything: how many
/// tries they have, so a first claim isn't a surprise later.
String claimAttemptsIntro(ClaimAttemptStatus s) =>
    'You can try up to ${s.maxAttempts} times for each post, so make your answer count.';

/// The warning at the top of the "File a claim" form, or null when there's
/// nothing to add. Before the limit is reached: which attempt this is and what
/// a rejection would cost; on the last attempt, an explicit warning.
String? claimDialogWarning(ClaimAttemptStatus s) {
  if (s.isLocked) return null;
  if (s.isLastAttempt) {
    return 'This is your last attempt (${s.nextAttemptNumber} of ${s.maxAttempts}). '
        "If it isn't approved you won't be able to claim this post again.";
  }
  if (s.attemptsUsed == 0) {
    return 'You have ${_attempts(s.maxAttempts)} for this post. '
        "If a claim isn't approved you can try again after a short wait.";
  }
  return 'Attempt ${s.nextAttemptNumber} of ${s.maxAttempts}. '
      "If it isn't approved you'll have ${_attempts(s.attemptsLeft - 1)} left.";
}

/// The chat banner after the person's latest claim was rejected — what
/// happened, what's left, and (while waiting) how long. [now] is for tests.
String claimRejectedMessage(ClaimAttemptStatus s, {DateTime? now}) {
  if (s.isLocked) {
    return "That claim wasn't approved, and you've used all ${s.maxAttempts} attempts, "
        "so this post can't be claimed again from your account. "
        'If you think this is a mistake, contact support.';
  }
  final wait = s.waitMinutes(now: now);
  final left = s.isLastAttempt
      ? 'You have 1 attempt left — your last, so check your answer carefully.'
      : 'You have ${_attempts(s.attemptsLeft)} left.';
  if (wait != null) {
    return "That claim wasn't approved. You can try again in about ${_minutes(wait)}. $left";
  }
  return "That claim wasn't approved. $left";
}
