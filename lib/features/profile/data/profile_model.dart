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
    this.phone,
    this.countryCode,
    this.tempCountryCode,
    this.tempCountryUntil,
    this.countryChangedAt,
  });

  final String id;
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final String? phone;

  /// The country whose posts this person sees in Browse (ISO code), or null
  /// if they haven't chosen one (the phone's region is used meanwhile).
  final String? countryCode;

  /// "Travelling" mode: browse another country's posts until [tempCountryUntil],
  /// then the home country comes back by itself.
  final String? tempCountryCode;
  final DateTime? tempCountryUntil;

  /// When the home country was last changed (the 30-day limit counts from here).
  final DateTime? countryChangedAt;

  /// The temporary country, only while it hasn't expired.
  String? get activeTempCountry {
    final until = tempCountryUntil;
    if (tempCountryCode == null || until == null) return null;
    return until.isAfter(DateTime.now()) ? tempCountryCode : null;
  }

  /// The earliest moment the home country can be changed again, or null if it
  /// can be changed now.
  DateTime? get nextCountryChangeAt {
    final changed = countryChangedAt;
    if (changed == null) return null;
    final next = changed.add(const Duration(days: 30));
    return next.isAfter(DateTime.now()) ? next : null;
  }
  final double rating;
  final int ratingCount;
  final bool isAdmin;

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'] as String,
      username: map['username'] as String?,
      fullName: map['full_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      phone: map['phone'] as String?,
      countryCode: map['country_code'] as String?,
      tempCountryCode: map['temp_country_code'] as String?,
      tempCountryUntil: map['temp_country_until'] == null
          ? null
          : DateTime.parse(map['temp_country_until'] as String),
      countryChangedAt: map['country_changed_at'] == null
          ? null
          : DateTime.parse(map['country_changed_at'] as String),
      rating: (map['rating'] as num).toDouble(),
      ratingCount: (map['rating_count'] as num).toInt(),
      isAdmin: map['is_admin'] as bool? ?? false,
    );
  }
}
