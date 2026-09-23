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
    this.imageSimilarity,
    this.textSimilarity,
    this.distanceMeters,
    this.timeProximity,
  });

  final String matchId;
  final String myItemId;
  final String myItemTitle;
  final String matchedItemId;
  final String matchedItemTitle;
  final String matchedItemType; // 'lost' | 'found'
  final String matchedItemUserId;
  final String? matchedItemImageUrl;

  /// The blended score shown as "XX% match" — see combined_match_score()
  /// in supabase/10_open_matching_and_time.sql for exactly how it's
  /// computed from the four fields below.
  final double similarityScore;

  /// Score breakdown — each null independently (not just all-or-nothing)
  /// depending on what data both items in the pair happen to have (a text
  /// embedding needs ai_service configured at post time; GPS/time need
  /// both posters to have shared a location/event time). The UI shows
  /// whichever of these are present rather than assuming all four always
  /// are.
  final double? imageSimilarity;
  final double? textSimilarity;
  final double? distanceMeters;

  /// 0..1, from time_proximity_score() — how close the two items'
  /// event_time values are, not a literal duration. See
  /// _ScoreBreakdown/MatchesScreen for where this becomes a human-readable
  /// "close in time" label instead of a raw score.
  final double? timeProximity;
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
      imageSimilarity: (map['image_similarity'] as num?)?.toDouble(),
      textSimilarity: (map['text_similarity'] as num?)?.toDouble(),
      distanceMeters: (map['distance_meters'] as num?)?.toDouble(),
      timeProximity: (map['time_proximity'] as num?)?.toDouble(),
      status: map['match_status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
