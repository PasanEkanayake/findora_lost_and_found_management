/// Mirrors a row in the `messages` table.
class MessageModel {
  const MessageModel({
    required this.id,
    required this.matchId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.createdAt,
    this.readAt,
    this.imagePath,
  });

  final String id;
  final String matchId;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Path of the photo in the private `chat-images` bucket, if this message
  /// carries one. [content] is then an optional caption (possibly empty).
  final String? imagePath;

  bool get hasImage => imagePath != null;

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      matchId: map['match_id'] as String,
      senderId: map['sender_id'] as String,
      receiverId: map['receiver_id'] as String,
      content: (map['content'] as String?) ?? '',
      imagePath: map['image_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] == null ? null : DateTime.parse(map['read_at'] as String),
    );
  }
}
