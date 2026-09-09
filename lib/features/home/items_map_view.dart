import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/location/current_location.dart';
import '../items/data/items_providers.dart';

/// Map view for the Browse tab, toggled from ItemFeedScreen's app bar.
/// Centers on the device's current location, then plots open items within
/// a fixed radius via the `nearby_items()` RPC. Deliberately doesn't share
/// the list view's category/search filters yet — combining both is a
/// reasonable next step once this is in daily use.
class ItemsMapView extends ConsumerStatefulWidget {
  const ItemsMapView({super.key});

  @override
  ConsumerState<ItemsMapView> createState() => _ItemsMapViewState();
}

class _ItemsMapViewState extends ConsumerState<ItemsMapView> {
  static const _radiusMeters = 5000;

  MapCenter? _center;
  bool _isLocating = true;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    setState(() => _isLocating = true);
    final position = await getCurrentPositionOrNull();
    if (!mounted) return;
    setState(() {
      _isLocating = false;
      _center = position == null ? null : MapCenter(position.latitude, position.longitude);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLocating) {
      return const Center(child: CircularProgressIndicator());
    }

    final center = _center;
    if (center == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_outlined,
                  size: 40, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('Location unavailable', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Enable location access to see items near you on a map.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadLocation, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final itemsAsync = ref.watch(nearbyItemsProvider(center));

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(
          "Couldn't load nearby items.",
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
      ),
      data: (items) {
        final markers = items.map((item) {
          return Marker(
            markerId: MarkerId(item.id),
            position: LatLng(item.latitude, item.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              item.isLost ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: item.title,
              snippet: [
                if (item.categoryName != null) item.categoryName!,
                if (item.locationLabel != null) item.locationLabel!,
              ].join(' · '),
            ),
          );
        }).toSet();

        return GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(center.latitude, center.longitude),
            zoom: 13,
          ),
          markers: markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
        );
      },
    );
  }
}
