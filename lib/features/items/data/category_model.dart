/// Mirrors a row in the `categories` table.
class CategoryModel {
  const CategoryModel({required this.id, required this.name, this.icon});

  final String id;
  final String name;
  final String? icon;

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String?,
    );
  }
}
