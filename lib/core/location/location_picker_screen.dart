import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
/// draggable [Marker]: the pin is really just an [Icon] pinned to the
/// screen's center in a [Stack], and what moves is the map underneath it
/// (tracked via [GoogleMap.onCameraMove]) — this reads as "drag the pin"
/// to the person using it, but avoids draggable-marker's occasional
/// platform-specific jank and imprecision on fast flings.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
  });

  final double initialLatitude;
  final double initialLongitude;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng _center;
  bool _isMoving = false;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    _center = LatLng(widget.initialLatitude, widget.initialLongitude);
  }

  Future<void> _confirm() async {
    setState(() => _isConfirming = true);
    String label = 'Custom location';
    try {
      final placemarks =
          await Geocoding().placemarkFromCoordinates(_center.latitude, _center.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.street, p.locality].where((s) => s != null && s.isNotEmpty);
        if (parts.isNotEmpty) label = parts.join(', ');
      }
    } catch (_) {
      // Coordinates alone are still useful without a friendly label.
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      PickedLocation(latitude: _center.latitude, longitude: _center.longitude, label: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 17),
            onCameraMoveStarted: () => setState(() => _isMoving = true),
            onCameraMove: (position) => _center = position.target,
            onCameraIdle: () => setState(() => _isMoving = false),
            myLocationButtonEnabled: false,
          ),

          // The fixed "pin" — see the class doc for why this isn't a
          // draggable Marker. Lifts slightly and casts a bigger shadow
          // while the map is moving, the same visual cue mapping apps
          // (Google Maps, Uber) use for this exact interaction.
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
                        'Drag the map so the pin sits exactly where the item was '
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

          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: FilledButton.icon(
              onPressed: _isConfirming ? null : _confirm,
              icon: _isConfirming
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isConfirming ? 'Saving…' : 'Use this location'),
            ),
          ),
        ],
      ),
    );
  }
}
