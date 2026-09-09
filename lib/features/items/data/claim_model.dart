/// Mirrors a row in the `claims` table.
class ClaimModel {
  const ClaimModel({
    required this.id,
    required this.itemId,
    required this.claimantId,
    required this.status,
    required this.createdAt,
    this.verificationAnswer,
  });

  final String id;
  final String itemId;
  final String claimantId;
  final String? verificationAnswer;
  final String status; // 'pending' | 'approved' | 'rejected'
  final DateTime createdAt;

  factory ClaimModel.fromMap(Map<String, dynamic> map) {
    return ClaimModel(
      id: map['id'] as String,
      itemId: map['item_id'] as String,
      claimantId: map['claimant_id'] as String,
      verificationAnswer: map['verification_answer'] as String?,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
