// Incoming links (a shared post opened from WhatsApp, a browser, a message...).
//
// The app understands two forms, both ending in the post's id:
//   https://<SHARE_BASE_URL host>/p/<id>   what the Share button sends
//   findora://open/p/<id>                  what the web preview page's
//                                          "Open in Findora" button uses
// Android hands the router just the path (/p/<id> or /open/p/<id>).

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// `/p/<id>` or `/open/p/<id>` -> `/item/<id>`; null for anything else —
/// including a path whose id isn't a well-formed uuid, so a mangled or
/// malicious link can never steer the app anywhere unexpected.
String? itemRouteForSharedPath(String path) {
  final segments = Uri.parse(path).pathSegments;
  List<String> rest;
  if (segments.length == 2 && segments[0] == 'p') {
    rest = segments;
  } else if (segments.length == 3 && segments[0] == 'open' && segments[1] == 'p') {
    rest = segments.sublist(1);
  } else {
    return null;
  }
  final id = rest[1];
  return _uuid.hasMatch(id) ? '/item/${id.toLowerCase()}' : null;
}

/// Where to go once the person has signed in, when a shared link was opened
/// while they were signed out. Set by the router's redirect, consumed (and
/// cleared) after login. A plain variable rather than a provider because it
/// is read and written inside the router's own redirect, where touching
/// provider state would be fragile — the same reason `rootRouter` is global.
String? pendingDeepLink;
