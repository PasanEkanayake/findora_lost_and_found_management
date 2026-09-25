import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../constants/app_constants.dart';

/// Result of running the on-device model on one photo.
class ClassificationResult {
  const ClassificationResult({
    required this.embedding,
    required this.label,
    required this.confidence,
  });

  /// The 1280-d pooled feature vector — this is what gets uploaded to
  /// Supabase and compared via pgvector for AI matching.
  final List<double> embedding;

  /// The highest-confidence ImageNet label, used to suggest a category.
  final String label;

  final double confidence;
}

/// MobileNetV2's input resolution.
const int _kInputSize = 224;

/// Wraps a single TFLite interpreter that outputs both the embedding and
/// the ImageNet classification from one forward pass — see
/// scripts/export_tflite_model.py for how that model file is built.
///
/// **Which output is which is detected from the model itself, not
/// assumed.** The TFLite converter does not promise to preserve the Keras
/// `outputs=[embedding, classification]` order, and the model this
/// project actually ships comes out the other way round
/// (output 0 = `[1, 1000]` classification, output 1 = `[1, 1280]`
/// embedding). An earlier version of this class hardcoded
/// `0 = embedding, 1 = classification`; every `classify()` call then threw
/// a shape-mismatch error, the post form swallowed it, and every item was
/// saved with no embedding — so the matching trigger never fired and the
/// Matches tab stayed empty with no visible error. [load] now inspects
/// each output tensor's shape (1280 wide = embedding, anything else =
/// classification) so it works with either ordering.
///
/// Create one instance and reuse it (see core/ml/tflite_provider.dart) —
/// reloading the model and label file from disk per photo would be
/// wasteful and would add unnecessary latency to every classification.
class TfliteClassifier {
  TfliteClassifier._(
    this._interpreter,
    this._labels,
    this._embeddingIndex,
    this._classIndex,
    this._classCount,
  );

  final Interpreter _interpreter;
  final List<String> _labels;

  /// Which of the interpreter's output tensors holds the 1280-d embedding.
  final int _embeddingIndex;

  /// Which output holds the class probabilities, or null for an
  /// embedding-only model (matching still works; auto-tagging just has no
  /// label to suggest).
  final int? _classIndex;
  final int _classCount;

  static Future<TfliteClassifier> load() async {
    final interpreter = await Interpreter.fromAsset(AppConstants.tfliteModelAsset);
    final labelsRaw = await rootBundle.loadString(AppConstants.tfliteLabelsAsset);
    final labels =
        labelsRaw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final outputs = interpreter.getOutputTensors();
    int? embeddingIndex;
    int? classIndex;
    var classCount = 0;
    for (var i = 0; i < outputs.length; i++) {
      final shape = outputs[i].shape;
      final width = shape.isEmpty ? 0 : shape.last;
      // Visible in the `flutter run` console — the first thing to check if
      // AI matching ever seems dead again.
      debugPrint('TFLite output $i: shape=$shape');
      if (width == AppConstants.embeddingDimension && embeddingIndex == null) {
        embeddingIndex = i;
      } else if (classIndex == null) {
        classIndex = i;
        classCount = width;
      }
    }

    if (embeddingIndex == null) {
      interpreter.close();
      throw StateError(
        'The bundled TFLite model has no ${AppConstants.embeddingDimension}-wide '
        'output, so it cannot produce image embeddings. Re-run '
        'scripts/export_tflite_model.py (see README, "AI matching setup").',
      );
    }

    debugPrint(
      'TFLite ready: embedding=output $embeddingIndex, '
      'classes=${classIndex == null ? "none" : "output $classIndex ($classCount)"}, '
      '${labels.length} labels',
    );
    return TfliteClassifier._(interpreter, labels, embeddingIndex, classIndex, classCount);
  }

  /// Convenience wrapper over [classifyBytes] for a photo on disk.
  Future<ClassificationResult> classify(File file) async {
    return classifyBytes(await file.readAsBytes());
  }

  /// Decodes, orients, resizes, and normalizes the encoded image [bytes]
  /// to match what `tf.keras.applications.mobilenet_v2.preprocess_input`
  /// expects (pixel values scaled to [-1, 1]), then runs the model.
  ///
  /// Takes bytes rather than only a [File] so the "scan my existing
  /// photos" flow (ItemsRepository.embedExistingImage) can classify a
  /// photo it just downloaded without writing a temp file first.
  Future<ClassificationResult> classifyBytes(Uint8List bytes) async {
    // Decoding and downscaling a multi-megapixel camera photo in pure Dart
    // is by far the slowest part of classification — do it on a
    // background isolate so the UI thread doesn't freeze while it runs.
    final rgb = await _decodeToRgbInBackground(bytes);
    final input = [_rgbToTensor(rgb)]; // wrap for the batch dimension

    // Output buffers are sized from the model's own tensors (see [load]),
    // and keyed by the tensor index each one really lives at.
    final embeddingOutput = [List<double>.filled(AppConstants.embeddingDimension, 0.0)];
    final classOutput = [List<double>.filled(_classCount, 0.0)];

    final outputs = <int, Object>{_embeddingIndex: embeddingOutput};
    final classIndex = _classIndex;
    if (classIndex != null) outputs[classIndex] = classOutput;

    _interpreter.runForMultipleInputs([input], outputs);

    final embedding = embeddingOutput[0];

    var label = 'unknown';
    var confidence = 0.0;
    if (classIndex != null && _classCount > 0) {
      final probabilities = classOutput[0];
      var bestIndex = 0;
      var bestScore = probabilities[0];
      for (var i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > bestScore) {
          bestScore = probabilities[i];
          bestIndex = i;
        }
      }
      label = bestIndex < _labels.length ? _labels[bestIndex] : 'unknown';
      confidence = bestScore;
    }

    return ClassificationResult(embedding: embedding, label: label, confidence: confidence);
  }

  List<List<List<double>>> _rgbToTensor(Uint8List rgb) {
    return List.generate(_kInputSize, (y) {
      return List.generate(_kInputSize, (x) {
        final o = (y * _kInputSize + x) * 3;
        return [
          (rgb[o] / 127.5) - 1.0,
          (rgb[o + 1] / 127.5) - 1.0,
          (rgb[o + 2] / 127.5) - 1.0,
        ];
      });
    });
  }

  void close() => _interpreter.close();
}

/// A top-level function (not a closure inside [TfliteClassifier]) on
/// purpose: `Isolate.run` copies everything its closure captures into the
/// new isolate, and a closure created inside an instance method can
/// capture `this` — i.e. the whole classifier, including its native
/// interpreter, which can't cross isolates. Nothing here can.
Future<Uint8List> _decodeToRgbInBackground(Uint8List bytes) {
  return Isolate.run(() => _decodeAndResizeToRgb(bytes));
}

/// Encoded image bytes -> `_kInputSize * _kInputSize * 3` raw RGB bytes.
///
/// Two details matter for matching quality, not just correctness:
/// - [img.bakeOrientation]: phone photos are usually stored sideways with
///   an EXIF "rotate me" tag, and `decodeImage` alone ignores it — so the
///   model would see the same object rotated 90° in one person's photo and
///   upright in another's (e.g. a camera shot vs. a screenshot), which
///   drags their embeddings apart.
/// - `Interpolation.average` when shrinking: the default (nearest
///   neighbour) just skips pixels when going from ~12MP down to 224px,
///   which aliases badly and makes two resolutions of the same photo
///   embed differently.
Uint8List _decodeAndResizeToRgb(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Could not decode image for classification.');
  }
  final upright = img.bakeOrientation(decoded);
  final resized = img.copyResize(
    upright,
    width: _kInputSize,
    height: _kInputSize,
    interpolation: img.Interpolation.average,
  );

  final out = Uint8List(_kInputSize * _kInputSize * 3);
  var o = 0;
  for (var y = 0; y < _kInputSize; y++) {
    for (var x = 0; x < _kInputSize; x++) {
      final pixel = resized.getPixel(x, y);
      out[o++] = _toByte(pixel.r);
      out[o++] = _toByte(pixel.g);
      out[o++] = _toByte(pixel.b);
    }
  }
  return out;
}

int _toByte(num value) {
  final v = value.round();
  if (v < 0) return 0;
  if (v > 255) return 255;
  return v;
}
