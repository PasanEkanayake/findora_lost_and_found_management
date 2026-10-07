import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'current_location.dart';

/// Result of manually adjusting a pin — always returned together so callers
/// never end up with coordinates and a label that disagree.
class PickedLocation {
  const PickedLocation({required this.latitude, required this.longitude, required this.label});

  final double latitude;
  final double longitude;
  final String label;
}

/// Lets the person drag the map to fine-tune exactly where a pin sits,
/// starting from wherever [initialLatitude]/[initialLongitude] already are
/// (typically the device's auto-detected position from
/// PostItemScreen's "Add current location"). This is the *adjustment*
/// step, not a replacement for auto-detect — GPS gets you close, but
/// "which side of the building" or "which bench in the park" often needs a
/// human eye.
///
/// Uses the fixed-center-pin-over-a-moving-map technique rather than a
/// draggable marker: the pin is really just an [Icon] pinned to the
/// screen's center in a [Stack], and what moves is the map underneath it
/// (tracked via onCameraMoveStarted/onCameraMove/onCameraIdle) — this reads
/// as "drag the pin" to the person using it, but avoids draggable-marker's
/// occasional platform-specific jank and imprecision on fast flings.
///
/// [initialLatitude]/[initialLongitude] may both be null (nothing detected or
/// typed yet). The picker then looks up the device's position itself instead
/// of opening on (0, 0) — which is open ocean, so the map looked like a
/// blank blue screen. If the device position isn't available either, it
/// opens on a zoomed-out world view and won't accept a pin until the person
/// has zoomed in to somewhere specific.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  /// Below this zoom the map shows a country or more — far too coarse for
  /// "where exactly did you lose it", so the pin can't be confirmed yet.
  static const _minConfirmZoom = 12.0;

  /// Where the map opens when there is nothing better to go on: the whole
  /// world, so the person can zoom in to wherever they are.
  static const _worldCenter = LatLng(20, 0);

  GoogleMapController? _mapController;
  LatLng? _center;
  double _zoom = 17;
  bool _isLocating = false;
  bool _hasDeviceFix = false;
  bool _noStartingPoint = false;
  bool _isMoving = false;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    final lat = widget.initialLatitude;
    final lng = widget.initialLongitude;
    if (lat != null && lng != null) {
      _center = LatLng(lat, lng);
    } else {
      _isLocating = true;
      _resolveStartingPoint();
    }
  }

  /// No coordinates were handed in — try the device's position, and if that
  /// isn't available fall back to the world view.
  Future<void> _resolveStartingPoint() async {
    final position = await getCurrentPositionOrNull()
        .timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (!mounted) return;
    setState(() {
      _isLocating = false;
      if (position != null) {
        _center = LatLng(position.latitude, position.longitude);
        _zoom = 17;
        _hasDeviceFix = true;
      } else {
        _center = _worldCenter;
        _zoom = 2;
        _noStartingPoint = true;
      }
    });
  }

  /// The "my location" button: recentres the map on the device.
  Future<void> _goToMyLocation() async {
    final position = await getCurrentPositionOrNull()
        .timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (!mounted) return;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't get your location. Check that location is on and allowed."),
        ),
      );
      return;
    }
    final target = LatLng(position.latitude, position.longitude);
    _center = target;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 17));
    setState(() {
      _hasDeviceFix = true;
      _noStartingPoint = false;
    });
  }

  Future<void> _confirm() async {
    final center = _center;
    if (center == null) return;
    setState(() => _isConfirming = true);

    var label = 'Pinned location';
    try {
      // geocoding 5.x replaced the old top-level placemarkFromCoordinates()
      // function with an instance method on the Geocoding class.
      final placemarks = await Geocoding().placemarkFromCoordinates(
        center.latitude,
        center.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        label = [p.street, p.locality]
            .where((part) => part != null && part.isNotEmpty)
            .join(', ');
        if (label.isEmpty) label = 'Pinned location';
      }
    } catch (_) {
      // Reverse geocoding can fail independently of the map itself — the
      // coordinates are still useful even without a friendly label.
    }

    if (!mounted) return;
    setState(() => _isConfirming = false);

    Navigator.of(context).pop(
      PickedLocation(latitude: center.latitude, longitude: center.longitude, label: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final center = _center;
    final canConfirm = !_isConfirming && center != null && _zoom >= _minConfirmZoom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust location'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          if (center != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: _zoom),
              onMapCreated: (controller) => _mapController = controller,
              onCameraMoveStarted: () => setState(() => _isMoving = true),
              onCameraMove: (position) {
                _center = position.target;
                _zoom = position.zoom;
              },
              onCameraIdle: () => setState(() => _isMoving = false),
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              // Only once a device fix proves permission was granted —
              // turning this on without permission can error on Android.
              myLocationEnabled: _hasDeviceFix,
            ),
          if (_isLocating)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Finding your location…'),
                ],
              ),
            ),

          // The fixed "pin" — see the class doc for why this isn't a
          // draggable marker. Lifts slightly and casts a bigger shadow
          // while the map is moving, the same visual cue mapping apps
          // (Google Maps, Uber) use for this exact interaction.
          if (center != null)
            IgnorePointer(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: _isMoving ? const Offset(0, -0.08) : Offset.zero,
                child: Padding(
                  // Anchors the pin's tip (not its center) to the map's
                  // actual center point.
                  padding: const EdgeInsets.only(bottom: 36),
                  child: Icon(
                    Icons.location_on,
                    size: 44,
                    color: theme.colorScheme.error,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: _isMoving ? 0.35 : 0.2),
                        blurRadius: _isMoving ? 10 : 4,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
          ),

          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.pan_tool_alt_outlined,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _noStartingPoint
                            ? "Couldn't find your location. Zoom in and drag the map so "
                                'the pin sits where the item was lost or found.'
                            : 'Drag the map so the pin sits exactly where the item was '
                                'lost or found.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (center != null)
            Positioned(
              right: 16,
              bottom: 88,
              child: FloatingActionButton.small(
                heroTag: 'picker_my_location',
                tooltip: 'My location',
                onPressed: _goToMyLocation,
                child: const Icon(Icons.my_location),
              ),
            ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: FilledButton.icon(
              onPressed: canConfirm ? _confirm : null,
              icon: _isConfirming
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _isConfirming
                    ? 'Saving…'
                    : (center != null && _zoom < _minConfirmZoom)
                        ? 'Zoom in to pick a spot'
                        : 'Use this location',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
