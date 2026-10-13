import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a failed database call into something fit to show a person.
///
/// Our own SQL functions and triggers raise errors whose text was written for
/// people — a rate limit ("Posting limit reached: 20 posts per day…", SQLSTATE
/// `RL001`) or a refused action ("A claim has already been filed for this
/// match…", `22023`). Those are shown as they are. Anything else — a network
/// failure, a row-level-security refusal, Postgres's own wording — is NOT
/// shown, since it would read as gibberish; [fallback] is used instead.
String friendlyDatabaseError(Object error, {required String fallback}) {
  if (error is PostgrestException && (error.code == 'RL001' || error.code == '22023')) {
    final message = error.message.trim();
    if (message.isNotEmpty) return message;
  }
  return fallback;
}
