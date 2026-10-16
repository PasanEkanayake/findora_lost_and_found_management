import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase sign-in session in the phone's encrypted storage (the
/// Android Keystore) instead of plain SharedPreferences.
///
/// Why: the default stores the access and refresh tokens as readable text in
/// the app's data folder, where a backup, a rooted phone or a malicious app
/// with file access can pick them up (OWASP MASVS-STORAGE). The refresh token
/// is effectively a long-lived password.
///
/// Anyone already signed in under the old storage is moved across the first
/// time the app reads the session, so nobody is signed out by this change.
///
/// If the encrypted store can't be read (a known Android issue after a
/// restore from backup or a lock-screen change corrupts the Keystore key), the
/// session is treated as missing — the person signs in again — rather than the
/// app crashing at start-up.
///
/// [LocalStorage] is an abstract class in supabase_flutter: this implements its
/// five methods.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage();

  // Default options on purpose: flutter_secure_storage picks the strongest
  // storage each Android version supports, and its option names have changed
  // between major versions.
  static const _storage = FlutterSecureStorage();

  static const _key = 'findora_supabase_session';

  /// Where supabase_flutter's default storage keeps the session.
  static const _legacyKey = 'SUPABASE_PERSIST_SESSION_KEY';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;

  @override
  Future<String?> accessToken() async {
    try {
      final stored = await _storage.read(key: _key);
      if (stored != null) return stored;
      return await _migrateLegacySession();
    } catch (e) {
      debugPrint('Secure session storage unreadable, treating as signed out: $e');
      try {
        await _storage.delete(key: _key);
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _storage.write(key: _key, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    await _storage.delete(key: _key);
    await _clearLegacySession();
  }

  /// Moves a session left by the old plain-text storage into the encrypted one
  /// and deletes the plain-text copy. Returns it, or null if there was none.
  static Future<String?> _migrateLegacySession() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_legacyKey);
    if (legacy == null) return null;
    await _storage.write(key: _key, value: legacy);
    await prefs.remove(_legacyKey);
    return legacy;
  }

  static Future<void> _clearLegacySession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyKey);
    } catch (_) {}
  }
}
