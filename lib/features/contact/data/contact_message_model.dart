/// Mirrors a row in the `contact_messages` table — the message bubbles
/// inside one ContactThreadModel's conversation.
class ContactMessageModel {
  const ContactMessageModel({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.readAt,
    this.imagePath,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Path of the photo in the private `chat-images` bucket, if any.
  final String? imagePath;

  bool get hasImage => imagePath != null;

  factory ContactMessageModel.fromMap(Map<String, dynamic> map) {
    return ContactMessageModel(
      id: map['id'] as String,
      threadId: map['thread_id'] as String,
      senderId: map['sender_id'] as String,
      content: (map['content'] as String?) ?? '',
      imagePath: map['image_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] == null ? null : DateTime.parse(map['read_at'] as String),
    );
  }
}
