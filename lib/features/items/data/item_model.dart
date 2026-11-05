/// Mirrors a row from the `items` table, joined with its category name and
/// photo URLs via `select('*, categories(name), item_images(image_url, thumb_url)')`.
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
    this.proofQuestion,
    this.countryCode,
    this.eventTime,
    this.imageUrls = const [],
    this.thumbnailUrl,
    this.expiresAt,
    this.posterName,
    this.categoryId,
  });

  final String id;
  final String userId;
  final String type; // 'lost' | 'found'
  final String status; // 'open' | 'matched' | 'claimed' | 'resolved' | 'expired'
  final String title;
  final DateTime createdAt;
  final String? description;
  final String? categoryName;
  final String? locationLabel;

  /// A question only the real owner could answer, set by whoever FOUND the
  /// item (never the answer — that lives in the owner-only `item_private`
  /// table). Shown to the claimant when they file a claim.
  final String? proofQuestion;

  /// ISO 3166-1 alpha-2 code of the country the post is in ("LK"). Null only
  /// for posts made before countries were required.
  final String? countryCode;

  /// The raw `items.category_id` value — `select('*')` already returns
  /// this column, it just wasn't being parsed into the model before,
  /// since nothing needed to *re-submit* a category until item editing
  /// did (EditItemScreen needs this to pre-select the right dropdown
  /// entry; [categoryName] alone isn't enough to look the id back up).
  final String? categoryId;

  /// When the item was actually lost/found, as reported by the poster —
  /// distinct from [createdAt] (when the report itself was posted), and
  /// optional since not everyone remembers or knows the exact time.
  final DateTime? eventTime;
  final List<String> imageUrls;

  /// What a LIST tile should show for this post's first photo: its small
  /// thumbnail when the server has made one, otherwise the full photo, or null
  /// for a post with no photo. Detail screens keep using [imageUrls]. See
  /// supabase/34_thumbnails.sql.
  final String? thumbnailUrl;

  /// Only populated when the query embeds `profiles(...)` (currently just
  /// ItemsRepository.fetchItemById, for the detail screen's "Posted by" /
  /// contact-thread naming) — null elsewhere, e.g. on feed/my-items cards
  /// that don't need it and shouldn't pay for the extra join.
  final String? posterName;

  bool get isLost => type == 'lost';

  /// When the post expires if its owner does nothing (60 days after posting or
  /// after the last renewal — supabase/35_post_expiry.sql). Null when the
  /// query didn't include it.
  final DateTime? expiresAt;

  /// The post ran out of time. It is hidden from other people and from
  /// matching, but its owner still sees it (marked Expired) and can renew it.
  bool get isExpired => status == 'expired';

  /// Whole days until it expires, rounded up (so "expires today" is 1 until
  /// the last moment); null if unknown, 0 once it has passed. [now] is for tests.
  int? daysUntilExpiry({DateTime? now}) {
    final at = expiresAt;
    if (at == null) return null;
    final remaining = at.difference(now ?? DateTime.now());
    if (remaining.isNegative) return 0;
    return (remaining.inMinutes / (24 * 60)).ceil();
  }

  /// Open and within [days] days of expiring — when the owner is nudged.
  bool isExpiringWithin(int days, {DateTime? now}) {
    if (status != 'open') return false;
    final left = daysUntilExpiry(now: now);
    return left != null && left <= days;
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    // A to-one relationship (items.category_id -> categories.id) comes back
    // as a single object; a to-many one (item_images.item_id -> items.id)
    // comes back as a list. Both can be null/empty if nothing matched.
    final categoryMap = map['categories'] as Map<String, dynamic>?;
    final profileMap = map['profiles'] as Map<String, dynamic>?;
    final imageRows = (map['item_images'] as List<dynamic>?) ?? const [];

    return ItemModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      type: map['type'] as String,
      status: map['status'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      categoryName: categoryMap?['name'] as String?,
      categoryId: map['category_id'] as String?,
      locationLabel: map['location_label'] as String?,
      proofQuestion: map['proof_question'] as String?,
      countryCode: map['country_code'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      eventTime:
          map['event_time'] == null ? null : DateTime.parse(map['event_time'] as String),
      imageUrls: imageRows
          .map((row) => (row as Map<String, dynamic>)['image_url'] as String)
          .toList(),
      expiresAt:
          map['expires_at'] == null ? null : DateTime.parse(map['expires_at'] as String).toLocal(),
      thumbnailUrl: imageRows.isEmpty
          ? null
          : ((imageRows.first as Map<String, dynamic>)['thumb_url'] as String?) ??
              (imageRows.first as Map<String, dynamic>)['image_url'] as String,
      posterName: profileMap == null
          ? null
          : ((profileMap['full_name'] as String?)?.trim().isNotEmpty ?? false)
              ? profileMap['full_name'] as String
              : (profileMap['username'] as String? ?? 'Findora user'),
    );
  }
}
