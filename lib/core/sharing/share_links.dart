import 'package:flutter_dotenv/flutter_dotenv.dart';

/// The public link people send each other for a post.
///
/// It points at the small web page described in
/// supabase/functions/post-preview/README.md (hosted next to
/// web/auth-callback.html), which opens the app if it's installed and
/// otherwise shows a preview with a "Get Findora" button. `SHARE_BASE_URL` in
/// `.env` is that page's address; without it the Share button is hidden,
/// since a link that goes nowhere would be worse than no link.
class ShareLinks {
  const ShareLinks._();

  /// `https://share.example.com/` -> `https://share.example.com`; null when
  /// blank or not an http(s) URL.
  static String? normaliseBaseUrl(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
      return null;
    }
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  /// The configured base URL, or null if there isn't a usable one.
  static String? get baseUrl {
    try {
      return normaliseBaseUrl(dotenv.maybeGet('SHARE_BASE_URL'));
    } catch (_) {
      return null; // .env not loaded (tests)
    }
  }

  static bool get isConfigured => baseUrl != null;

  /// `<base>/p/<id>`, or null when sharing isn't configured. [baseUrl]
  /// overrides the configured one (for tests).
  static String? postUrl(String itemId, {String? baseUrl}) {
    final base = normaliseBaseUrl(baseUrl) ?? ShareLinks.baseUrl;
    return base == null ? null : '$base/p/$itemId';
  }

  /// The message that goes with the link in the share sheet. Only the title:
  /// nothing from the description, the poster or the location.
  static String shareText({required bool isLost, required String title, required String url}) {
    return '${isLost ? 'Lost' : 'Found'}: $title\nSee it on Findora: $url';
  }
}
