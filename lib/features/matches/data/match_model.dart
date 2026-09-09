/// Mirrors one row returned by the `my_matches()` Postgres function, which
/// already resolves "my item" vs "the matched item" from the caller's
/// perspective — see supabase/02_functions_and_triggers.sql.
class MatchModel {
  const MatchModel({
    required this.matchId,
    required this.myItemId,
    required this.myItemTitle,
    required this.matchedItemId,
    required this.matchedItemTitle,
    required this.matchedItemType,
    required this.matchedItemUserId,
    required this.similarityScore,
    required this.status,
    required this.createdAt,
    this.matchedItemImageUrl,
  });

  final String matchId;
  final String myItemId;
  final String myItemTitle;
  final String matchedItemId;
  final String matchedItemTitle;
  final String matchedItemType; // 'lost' | 'found'
  final String matchedItemUserId;
  final String? matchedItemImageUrl;
  final double similarityScore;
  final String status; // 'pending' | 'confirmed' | 'dismissed'
  final DateTime createdAt;

  bool get matchedItemIsLost => matchedItemType == 'lost';

  factory MatchModel.fromMap(Map<String, dynamic> map) {
    return MatchModel(
      matchId: map['match_id'] as String,
      myItemId: map['my_item_id'] as String,
      myItemTitle: map['my_item_title'] as String,
      matchedItemId: map['matched_item_id'] as String,
      matchedItemTitle: map['matched_item_title'] as String,
      matchedItemType: map['matched_item_type'] as String,
      matchedItemUserId: map['matched_item_user_id'] as String,
      matchedItemImageUrl: map['matched_item_image_url'] as String?,
      similarityScore: (map['similarity_score'] as num).toDouble(),
      status: map['match_status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
