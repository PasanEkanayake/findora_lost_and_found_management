import 'package:intl/intl.dart';

/// The words shown when an email address can't be used to sign up yet (a
/// recently deleted account is in its cooldown, or moderation blocked the
/// address — supabase/16_release_email_on_delete.sql). One place, so signing up
/// with email and signing up with Google say the same thing.
String emailCooldownMessage(DateTime? retryAt) {
  if (retryAt == null) return "This email can't be used to create an account.";
  final date = DateFormat.yMMMd().format(retryAt.toLocal());
  return 'An account with this email was recently deleted. '
      'You can sign up with it again on $date.';
}

/// Shown when a Google sign-up is refused and the app can't tell the date.
///
/// With Google the app only learns the address AFTER Google has handed it to
/// Supabase, and Supabase turns the database's refusal into a generic
/// "Database error saving new user" — so the date is unknown here unless the
/// optional `before user created` hook (supabase/37_signup_hook.sql) is on, in
/// which case [friendlyAuthErrorMessage] passes its exact message through.
const String kGoogleSignupBlockedMessage =
    "We couldn't create a Findora account for this Google account. If an account "
    'with this email was recently deleted, you can sign up with it again once '
    'the waiting period (usually 14 days) has passed.';

const _hookCooldownPhrase = 'An account with this email was recently deleted';
const _hookPermanentPhrase = "This email can't be used to create an account";

/// Turns the text of an auth error that came back through a sign-in redirect
/// into something fit to show a person.
///
/// * the exact message from the database hook (with the date) — passed
///   through, minus any prefix Supabase put in front of it;
/// * the generic "Database error saving new user" (what a blocked sign-up
///   looks like without the hook) — the Google wording above;
/// * anything else — unchanged.
String friendlyAuthErrorMessage(String raw) {
  for (final phrase in [_hookCooldownPhrase, _hookPermanentPhrase]) {
    final at = raw.indexOf(phrase);
    if (at >= 0) return raw.substring(at).trim();
  }
  if (raw.toLowerCase().contains('database error saving new user')) {
    return kGoogleSignupBlockedMessage;
  }
  return raw;
}
