import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart'
    show RealtimeChannel, RealtimeSubscribeStatus;

import '../../../core/supabase/supabase_client.dart';

/// "The other person is typing…" for one open conversation.
///
/// Uses Supabase Realtime *Broadcast*: tiny messages passed between the two
/// open chat screens through a channel, never written to the database. Each
/// side tells the channel "typing" / "stopped"; [otherTyping] is true while
/// the other person's latest "typing" is fresh.
///
/// Everything here is best effort — if the channel isn't connected, nothing
/// shows and nothing breaks.
class TypingChannel {
  TypingChannel({required this.topic, required this.myId});

  /// Unique per conversation, e.g. `typing:m:<match id>` (see
  /// supabase/30_chat_photos.sql for why that is private enough).
  final String topic;
  final String myId;

  /// True while the other person is typing. Listen to this to show the dots.
  final ValueNotifier<bool> otherTyping = ValueNotifier<bool>(false);

  /// Send "still typing" at most this often while someone keeps typing.
  static const Duration _resend = Duration(milliseconds: 2500);

  /// With no word from the other side for this long, assume they stopped (a
  /// lost "stopped" message, a closed app).
  static const Duration _expireAfter = Duration(seconds: 5);

  /// Typing that goes quiet this long counts as stopped.
  static const Duration _idleAfter = Duration(seconds: 3);

  RealtimeChannel? _channel;
  bool _subscribed = false;
  bool _disposed = false;
  bool _iAmTyping = false;
  DateTime? _lastSent;
  Timer? _expireTimer;
  Timer? _idleTimer;

  /// Opens the channel. Call once, when the chat screen opens.
  void start() {
    final channel = supabase.channel(topic);
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        // Depending on the library version the callback gets the event's own
        // data or an envelope with it under `payload`; accept both.
        final inner = payload['payload'];
        final data = inner is Map ? inner : payload;
        if (data['user_id'] == myId) return;
        _setOther(data['typing'] == true);
      },
    ).subscribe((status, error) {
      _subscribed = status == RealtimeSubscribeStatus.subscribed;
      if (error != null) debugPrint('typing channel [$topic]: $status $error');
    });
    _channel = channel;
  }

  void _setOther(bool typing) {
    if (_disposed) return;
    _expireTimer?.cancel();
    otherTyping.value = typing;
    if (typing) {
      _expireTimer = Timer(_expireAfter, () {
        if (!_disposed) otherTyping.value = false;
      });
    }
  }

  /// A message from the other person just arrived, so they're no longer
  /// "typing" it.
  void otherSentMessage() => _setOther(false);

  /// Call as the text box changes: [hasText] is whether it holds anything.
  void typed(bool hasText) {
    if (_disposed) return;
    if (!hasText) {
      stopTyping();
      return;
    }
    final now = DateTime.now();
    if (!_iAmTyping || _lastSent == null || now.difference(_lastSent!) >= _resend) {
      _send(true);
      _lastSent = now;
    }
    _iAmTyping = true;
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleAfter, stopTyping);
  }

  /// Tell the other side "stopped" — after sending, clearing the box, going
  /// quiet or leaving the screen.
  void stopTyping() {
    _idleTimer?.cancel();
    if (!_iAmTyping) return;
    _iAmTyping = false;
    _lastSent = null;
    _send(false);
  }

  void _send(bool typing) {
    final channel = _channel;
    if (channel == null || !_subscribed) return;
    try {
      unawaited(
        channel
            .sendBroadcastMessage(event: 'typing', payload: {'user_id': myId, 'typing': typing})
            .then<void>((_) {}, onError: (Object _) {}),
      );
    } catch (_) {
      // Best effort.
    }
  }

  void dispose() {
    if (_disposed) return;
    stopTyping();
    _disposed = true;
    _expireTimer?.cancel();
    _idleTimer?.cancel();
    final channel = _channel;
    if (channel != null) unawaited(supabase.removeChannel(channel));
    otherTyping.dispose();
  }
}
