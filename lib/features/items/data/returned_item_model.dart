/// One row of `my_returned_items()` (supabase/13_returned_items_and_ratings.sql):
/// a post of the signed-in user's that was handed back, together with the
/// post it was returned with.
///
/// The "other" fields are nullable because a post returned before that
/// migration may have no counterpart recorded — it's still listed, just
/// without the other side.
class ReturnedItemModel {
  const ReturnedItemModel({
    required this.myItemId,
    required this.myItemTitle,
    required this.myItemType,
    required this.otherUserName,
    required this.resolvedAt,
    this.myItemImageUrl,
    this.otherItemId,
    this.otherItemTitle,
    this.otherItemType,
    this.otherItemImageUrl,
    this.otherUserId,
    this.matchId,
    this.starsIGave,
    this.starsIReceived,
  });

  final String myItemId;
  final String myItemTitle;
  final String myItemType; // 'lost' | 'found'
  final String? myItemImageUrl;

  final String? otherItemId;
  final String? otherItemTitle;
  final String? otherItemType;
  final String? otherItemImageUrl;
  final String? otherUserId;
  final String otherUserName;

  /// The confirmed match between the two posts — what the chat is keyed on.
  final String? matchId;
  final DateTime resolvedAt;

  /// 1–5, or null if that rating hasn't been given yet.
  final int? starsIGave;
  final int? starsIReceived;

  bool get hasCounterpart => otherItemId != null;
  bool get iHaveRated => starsIGave != null;

  /// A chat can only be reopened if everything ChatScreen needs is known.
  bool get canOpenChat =>
      matchId != null &&
      otherUserId != null &&
      otherItemId != null &&
      otherItemTitle != null &&
      otherItemType != null;

  factory ReturnedItemModel.fromMap(Map<String, dynamic> map) {
    return ReturnedItemModel(
      myItemId: map['my_item_id'] as String,
      myItemTitle: map['my_item_title'] as String,
      myItemType: map['my_item_type'] as String,
      myItemImageUrl: map['my_item_image_url'] as String?,
      otherItemId: map['other_item_id'] as String?,
      otherItemTitle: map['other_item_title'] as String?,
      otherItemType: map['other_item_type'] as String?,
      otherItemImageUrl: map['other_item_image_url'] as String?,
      otherUserId: map['other_user_id'] as String?,
      otherUserName: (map['other_user_name'] as String?) ?? 'Findora user',
      matchId: map['match_id'] as String?,
      resolvedAt: DateTime.parse(map['resolved_at'] as String).toLocal(),
      starsIGave: (map['stars_i_gave'] as num?)?.toInt(),
      starsIReceived: (map['stars_i_received'] as num?)?.toInt(),
    );
  }
}
