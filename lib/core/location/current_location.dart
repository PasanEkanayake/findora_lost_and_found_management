import 'package:geolocator/geolocator.dart';

/// Requests the current device position, handling the service-enabled and
/// permission dance in one place. Returns null (rather than throwing) when
/// location isn't available for any reason — callers should treat that as
/// "fall back to a default/prompt", not a crash. Used by both the
/// post-item location picker and the map view.
Future<Position?> getCurrentPositionOrNull() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition();
  } catch (_) {
    return null;
  }
}
