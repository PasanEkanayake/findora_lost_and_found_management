/// Mirrors a row in the `profiles` table — the signed-in user's own
/// profile, including fields Supabase Auth's `User` object doesn't carry
/// (rating, admin flag).
class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.rating,
    required this.ratingCount,
    required this.isAdmin,
    this.username,
    this.fullName,
    this.avatarUrl,
  });

  final String id;
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final double rating;
  final int ratingCount;
  final bool isAdmin;

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'] as String,
      username: map['username'] as String?,
      fullName: map['full_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      rating: (map['rating'] as num).toDouble(),
      ratingCount: (map['rating_count'] as num).toInt(),
      isAdmin: map['is_admin'] as bool? ?? false,
    );
  }
}
