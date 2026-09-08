/// Mirrors a row from the `items` table, joined with its category name and
/// photo URLs via `select('*, categories(name), item_images(image_url)')`.
class ItemModel {
  const ItemModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.status,
    required this.title,
    required this.createdAt,
    this.description,
    this.categoryName,
    this.locationLabel,
    this.imageUrls = const [],
  });

  final String id;
  final String userId;
  final String type; // 'lost' | 'found'
  final String status; // 'open' | 'matched' | 'claimed' | 'resolved'
  final String title;
  final DateTime createdAt;
  final String? description;
  final String? categoryName;
  final String? locationLabel;
  final List<String> imageUrls;

  bool get isLost => type == 'lost';

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    // A to-one relationship (items.category_id -> categories.id) comes back
    // as a single object; a to-many one (item_images.item_id -> items.id)
    // comes back as a list. Both can be null/empty if nothing matched.
    final categoryMap = map['categories'] as Map<String, dynamic>?;
    final imageRows = (map['item_images'] as List<dynamic>?) ?? const [];

    return ItemModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      type: map['type'] as String,
      status: map['status'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      categoryName: categoryMap?['name'] as String?,
      locationLabel: map['location_label'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      imageUrls: imageRows
          .map((row) => (row as Map<String, dynamic>)['image_url'] as String)
          .toList(),
    );
  }
}
