/// Mirrors a row from the `nearby_items()` RPC — a map-friendly shape
/// with plain lat/lng doubles rather than a raw PostGIS geography value,
/// which doesn't serialize predictably over PostgREST.
class NearbyItemModel {
  const NearbyItemModel({
    required this.id,
    required this.title,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.categoryName,
    this.locationLabel,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String type; // 'lost' | 'found'
  final String? categoryName;
  final String? locationLabel;
  final double latitude;
  final double longitude;
  final String? imageUrl;

  bool get isLost => type == 'lost';

  factory NearbyItemModel.fromMap(Map<String, dynamic> map) {
    return NearbyItemModel(
      id: map['id'] as String,
      title: map['title'] as String,
      type: map['type'] as String,
      categoryName: map['category_name'] as String?,
      locationLabel: map['location_label'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      imageUrl: map['image_url'] as String?,
    );
  }
}
