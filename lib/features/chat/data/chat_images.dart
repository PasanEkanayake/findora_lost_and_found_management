import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';

/// Which kind of conversation a photo belongs to. The letter is the first
/// folder of its storage path (see supabase/30_chat_photos.sql).
enum ChatKind {
  /// The confirmed-match chat (`messages`, folder id = match id).
  match('m'),

  /// A direct "Contact poster" thread (`contact_messages`, folder id = thread id).
  thread('c');

  const ChatKind(this.folder);
  final String folder;
}

class _SignedUrl {
  const _SignedUrl(this.url, this.expires);
  final String url;
  final DateTime expires;
}

/// Photos sent inside chats. They live in a PRIVATE bucket — only the two
/// people in the conversation can read them — so showing one means asking
/// Supabase for a short-lived signed link first.
class ChatImages {
  const ChatImages();

  /// A signed link is valid for an hour; one is reused for 50 minutes so
  /// scrolling a long chat doesn't ask again for every photo.
  static const int _validSeconds = 3600;
  static const Duration _reuseFor = Duration(minutes: 50);
  static final Map<String, _SignedUrl> _cache = {};

  static String _extensionOf(String filePath) {
    final dot = filePath.lastIndexOf('.');
    final ext = dot == -1 ? '' : filePath.substring(dot + 1).toLowerCase();
    return (ext == 'png' || ext == 'webp') ? ext : 'jpg';
  }

  /// Uploads [file] into the conversation's folder and returns the storage
  /// path to put on the message. Throws if the upload fails.
  Future<String> upload({
    required ChatKind kind,
    required String conversationId,
    required File file,
  }) async {
    final path = '${kind.folder}/$conversationId/${const Uuid().v4()}.${_extensionOf(file.path)}';
    await supabase.storage.from(AppConstants.chatImagesBucket).upload(path, file);
    return path;
  }

  /// Removes a photo that was uploaded but never made it into a message.
  /// Best effort: a failure just leaves an orphan file, nothing user-visible.
  Future<void> deleteQuietly(String path) async {
    try {
      await supabase.storage.from(AppConstants.chatImagesBucket).remove([path]);
    } catch (e) {
      debugPrint('Chat photo cleanup failed for $path: $e');
    }
  }

  /// A link the app can load [path] from, reused while it is still fresh.
  Future<String> signedUrl(String path) async {
    final cached = _cache[path];
    if (cached != null && cached.expires.isAfter(DateTime.now())) return cached.url;
    final url = await supabase.storage
        .from(AppConstants.chatImagesBucket)
        .createSignedUrl(path, _validSeconds);
    _cache[path] = _SignedUrl(url, DateTime.now().add(_reuseFor));
    return url;
  }
}

final chatImagesProvider = Provider<ChatImages>((ref) => const ChatImages());

/// The signed link for one photo path. autoDispose: cheap to ask again (the
/// repository keeps the link for 50 minutes), and nothing is held for photos
/// scrolled far out of view.
final chatImageUrlProvider = FutureProvider.autoDispose.family<String, String>((ref, path) {
  return ref.watch(chatImagesProvider).signedUrl(path);
});
