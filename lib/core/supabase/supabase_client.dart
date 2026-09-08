import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared accessor for the already-initialized Supabase client (see
/// `Supabase.initialize()` in main.dart). Kept in its own file rather than
/// only as a top-level variable in main.dart so any file — screens,
/// providers, the router — can import just this, without pulling in
/// app-wide widget code or risking circular imports.
final supabase = Supabase.instance.client;
