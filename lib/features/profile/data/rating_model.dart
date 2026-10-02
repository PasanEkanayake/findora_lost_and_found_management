/// One row of `my_ratings()` (supabase/13_returned_items_and_ratings.sql):
/// a rating the signed-in user either received or gave.
class RatingModel {
  const RatingModel({
    required this.id,
    required this.isReceived,
    required this.stars,
    required this.createdAt,
    required this.otherUserName,
    this.comment,
    this.itemTitle,
  });

  final String id;

  /// True: someone rated me. False: I rated someone.
  final bool isReceived;
  final int stars;
  final String? comment;
  final DateTime createdAt;
  final String otherUserName;

  /// Title of the item the return was about; null if it can't be read any
  /// more (e.g. the post was removed).
  final String? itemTitle;

  factory RatingModel.fromMap(Map<String, dynamic> map) {
    final comment = (map['comment'] as String?)?.trim();
    return RatingModel(
      id: map['rating_id'] as String,
      isReceived: map['direction'] == 'received',
      stars: (map['stars'] as num).toInt(),
      comment: (comment == null || comment.isEmpty) ? null : comment,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      otherUserName: (map['other_user_name'] as String?) ?? 'Findora user',
      itemTitle: map['item_title'] as String?,
    );
  }
}
