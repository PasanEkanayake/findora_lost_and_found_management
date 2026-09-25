import 'dart:convert';

import 'package:http/http.dart' as http;

/// Calls the optional AI matching microservice (see ai_service/) to turn an
/// item's title + description into a 384-d sentence embedding for the NLP
/// side of multimodal matching (see supabase/05_multimodal_matching.sql).
///
/// This is genuinely optional infrastructure, not a required backend:
/// nothing here is on-device (unlike the CNN classifier in tflite_
/// classifier.dart), so if `AI_SERVICE_URL` isn't configured, or the call
/// times out, or the service is just down, every caller treats a null
/// result as "post without a text embedding" rather than an error — the
/// item still gets image-similarity matching from the on-device model, it
/// just doesn't get the text-similarity boost until this succeeds (see
/// ItemsRepository.createItem and PostItemScreen).
class TextEmbeddingService {
  const TextEmbeddingService(this._baseUrl);

  /// Null when `AI_SERVICE_URL` isn't set in .env — see [tryEmbed].
  final String? _baseUrl;

  /// Fire-and-forget ping to the service's `/health` endpoint, meant to be
  /// called as soon as the post form opens. Free-tier hosts (Render,
  /// Railway, ...) put an idle service to sleep, and waking it up plus
  /// loading the sentence-transformer model can take 30-60 seconds — far
  /// longer than [tryEmbed]'s 6-second budget. Without this, the *first*
  /// post after a quiet spell reliably times out and goes up with no text
  /// embedding (so no text-similarity signal on its matches). Pinging
  /// early gives the service the time it takes to fill out the form to
  /// wake up. Never throws, never blocks, safe to call repeatedly.
  void warmUp() {
    final baseUrl = _baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) return;
    http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 90))
        .then<void>((_) {}, onError: (Object _) {});
  }

  /// Best-effort: returns null on any failure (missing config, timeout,
  /// non-200, malformed response) instead of throwing, so callers never
  /// need a try/catch of their own around this — see the class doc for why
  /// that's the right default here.
  Future<List<double>?> tryEmbed({required String title, String? description}) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/embed/text'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'title': title, 'description': description ?? ''}),
          )
          // Posting an item shouldn't hang indefinitely on a slow/asleep
          // microservice (free-tier hosts often cold-start) — a few
          // seconds is enough to be worth waiting for without the form
          // feeling stuck.
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final embedding = body['embedding'] as List<dynamic>?;
      if (embedding == null) return null;

      return embedding.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return null;
    }
  }
}
