import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client.dart';

/// Emits on every auth state change (sign in, sign out, token refresh,
/// etc.). Riverpod's StreamProvider keeps exactly one subscription alive
/// for as long as anything is watching it, so the router, the profile
/// screen, and anything added in later phases all react to the same
/// underlying stream instead of each opening their own.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// Convenience accessor for the currently signed-in user, or null.
/// Re-evaluates whenever [authStateChangesProvider] emits — screens should
/// watch this instead of reading `supabase.auth.currentUser` directly, or
/// they won't rebuild when the session changes.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateChangesProvider);
  return supabase.auth.currentUser;
});
