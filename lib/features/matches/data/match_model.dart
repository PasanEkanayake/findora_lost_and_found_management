/// Mirrors one row returned by the `my_matches()` Postgres function, which
/// already resolves "my item" vs "the matched item" from the caller's
/// perspective — see supabase/02_functions_and_triggers.sql.
/// How much to trust a match. The percentage is a calibrated *evidence score*,
/// not a probability, so the app leads with the tier. Mirrors the thresholds
/// described in supabase/18_calibrated_match_score.sql — if you change one,
/// change the other.
enum MatchTier {
  strong('Strong'),
  likely('Likely'),
  possible('Possible');

  const MatchTier(this.label);

  final String label;

  static const double strongFrom = 0.80;
  static const double likelyFrom = 0.55;

  static MatchTier fromScore(double score) {
    if (score >= strongFrom) return strong;
    if (score >= likelyFrom) return likely;
    return possible;
  }
}

/// The Matches tab's filter chips. Applied on the server (the list is paged,
/// so filtering what's already on the phone would hide matches that simply
/// haven't been loaded yet).
enum MatchFilter {
  all('all'),
  imageOnly('image'),
  textOnly('text'),
  both('both'),
  nearby('nearby'),
  time('time');

  const MatchFilter(this.rpcValue);

  /// The `p_filter` value `my_matches_page()` understands.
  final String rpcValue;
}

/// The minimum photo similarity at which two photos count as "agreeing" —
/// matching_threshold() in the database (supabase/11_realtime_and_matching_fixes.sql).
const double kImageAgreesFrom = 0.60;

/// The minimum wording similarity that counts as "agreeing".
const double kTextAgreesFrom = 0.50;

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
    this.myItemImageUrl,
    this.imageSimilarity,
    this.textSimilarity,
    this.distanceMeters,
    this.timeProximity,
    this.myDecision,
    this.otherConfirmed = false,
    this.reopenable = true,
  });

  final String matchId;
  final String myItemId;
  final String myItemTitle;
  final String matchedItemId;
  final String matchedItemTitle;
  final String matchedItemType; // 'lost' | 'found'
  final String matchedItemUserId;
  final String? matchedItemImageUrl;

  /// The caller's own item's first photo (`my_matches_page()` returns it so
  /// the match card can show both items side by side). Null if the item has
  /// no photo.
  final String? myItemImageUrl;

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
  /// The overall state. 'confirmed' means BOTH people confirmed (that is what
  /// opens the chat); 'dismissed' means either said "Not a match"; 'pending'
  /// is everything else, including "I confirmed, they haven't yet".
  final String status; // 'pending' | 'confirmed' | 'dismissed'
  final DateTime createdAt;

  /// My own decision: null (none yet), 'confirmed' or 'dismissed'.
  final String? myDecision;

  /// True when the OTHER person has confirmed. Only "confirmed" is ever
  /// shared with the other side — a "Not a match" simply ends the match.
  final bool otherConfirmed;

  /// Whether Undo does anything: false when the match is dismissed only
  /// because the other person dismissed it (my Undo could not reopen it).
  final bool reopenable;

  /// Open, and I haven't decided: the Confirm / Not a match buttons show.
  bool get needsMyInput => status == 'pending' && myDecision != 'confirmed';

  /// I confirmed and we're waiting for the other person to do the same.
  bool get waitingForOther => status == 'pending' && myDecision == 'confirmed';

  /// The other person already confirmed — my "This is it!" makes it mutual.
  bool get otherConfirmedFirst => needsMyInput && otherConfirmed;

  bool get matchedItemIsLost => matchedItemType == 'lost';

  MatchTier get tier => MatchTier.fromScore(similarityScore);

  /// A photo score is now recorded for EVERY pair whose posts both have an
  /// analysed photo — including low ones, which are shown (they explain a low
  /// match) — so "the photos agree" means the score clears the threshold, not
  /// merely that it exists.
  bool get photosAgree => imageSimilarity != null && imageSimilarity! >= kImageAgreesFrom;

  bool get wordingAgrees => textSimilarity != null && textSimilarity! >= kTextAgreesFrom;

  /// Matches only ever pair a lost item with a found one, so my item is
  /// always the opposite type of the matched one.
  bool get myItemIsLost => !matchedItemIsLost;

  factory MatchModel.fromMap(Map<String, dynamic> map, {String? myItemImageUrl}) {
    return MatchModel(
      matchId: map['match_id'] as String,
      myItemId: map['my_item_id'] as String,
      myItemTitle: map['my_item_title'] as String,
      matchedItemId: map['matched_item_id'] as String,
      matchedItemTitle: map['matched_item_title'] as String,
      matchedItemType: map['matched_item_type'] as String,
      matchedItemUserId: map['matched_item_user_id'] as String,
      matchedItemImageUrl: map['matched_item_image_url'] as String?,
      myItemImageUrl: myItemImageUrl ?? map['my_item_image_url'] as String?,
      myDecision: map['my_decision'] as String?,
      otherConfirmed: (map['other_confirmed'] as bool?) ?? false,
      reopenable: (map['reopenable'] as bool?) ?? true,
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
