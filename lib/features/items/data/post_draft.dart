import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The text parts of an unfinished "Report an item" form, saved on the phone so
/// a call, a crash or a swipe-away doesn't cost someone the description they
/// were typing. Photos aren't kept (the files may be gone by next time) —
/// the person re-adds them.
class PostDraft {
  const PostDraft({
    required this.type,
    required this.title,
    required this.description,
    required this.categoryId,
    required this.proofQuestion,
    required this.proofAnswer,
  });

  final String type;
  final String title;
  final String description;
  final String? categoryId;
  final String proofQuestion;
  final String proofAnswer;

  /// A draft with nothing worth restoring is never saved.
  bool get isEmpty =>
      title.trim().isEmpty &&
      description.trim().isEmpty &&
      proofQuestion.trim().isEmpty &&
      proofAnswer.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'description': description,
        'categoryId': categoryId,
        'proofQuestion': proofQuestion,
        'proofAnswer': proofAnswer,
      };

  static PostDraft? fromJson(Object? decoded) {
    if (decoded is! Map) return null;
    final type = decoded['type'];
    if (type != 'lost' && type != 'found') return null;
    String text(String key) => (decoded[key] as String?) ?? '';
    return PostDraft(
      type: type as String,
      title: text('title'),
      description: text('description'),
      categoryId: decoded['categoryId'] as String?,
      proofQuestion: text('proofQuestion'),
      proofAnswer: text('proofAnswer'),
    );
  }
}

/// Reads and writes the single saved draft. Every method swallows storage
/// errors: losing a draft must never get in the way of posting.
class PostDraftStore {
  const PostDraftStore();

  static const _key = 'post_draft_v1';

  Future<PostDraft?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final draft = PostDraft.fromJson(jsonDecode(raw));
      return (draft == null || draft.isEmpty) ? null : draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PostDraft draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (draft.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode(draft.toJson()));
      }
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
