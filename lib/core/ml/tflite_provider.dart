import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tflite_classifier.dart';

/// Loads the on-device model once and keeps it cached for the app's
/// lifetime — deliberately not `.autoDispose`, since reloading a
/// multi-megabyte model every time a screen is revisited would be
/// wasteful. If assets/models/ doesn't have the model file yet (see
/// scripts/export_tflite_model.py), this provider ends up in an error
/// state; callers should treat that as "skip the AI features for now",
/// not as a reason to crash — see how post_item_screen.dart handles it.
final tfliteClassifierProvider = FutureProvider<TfliteClassifier>((ref) async {
  final classifier = await TfliteClassifier.load();
  ref.onDispose(classifier.close);
  return classifier;
});
