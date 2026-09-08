import 'dart:io';

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

/// Wraps a single TFLite interpreter that outputs both the embedding and
/// the ImageNet classification from one forward pass — see
/// scripts/export_tflite_model.py for exactly how that model file is
/// built, including the printed output-tensor order you should
/// double-check against the indices used in [classify] below.
///
/// Create one instance and reuse it (see core/ml/tflite_provider.dart) —
/// reloading the model and label file from disk per photo would be
/// wasteful and would add unnecessary latency to every classification.
class TfliteClassifier {
  TfliteClassifier._(this._interpreter, this._labels);

  final Interpreter _interpreter;
  final List<String> _labels;

  static const _inputSize = 224;

  static Future<TfliteClassifier> load() async {
    final interpreter = await Interpreter.fromAsset(AppConstants.tfliteModelAsset);
    final labelsRaw = await rootBundle.loadString(AppConstants.tfliteLabelsAsset);
    final labels =
        labelsRaw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return TfliteClassifier._(interpreter, labels);
  }

  /// Decodes, resizes, and normalizes [file] to match what
  /// `tf.keras.applications.mobilenet_v2.preprocess_input` expects (pixel
  /// values scaled to [-1, 1]), then runs the model.
  Future<ClassificationResult> classify(File file) async {
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image for classification.');
    }
    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);
    final input = [_imageToTensor(resized)]; // wrap for the batch dimension

    // Output shapes match the two-output model exported by
    // scripts/export_tflite_model.py: [1, 1280] embedding, [1, N] labels.
    final embeddingOutput = [List<double>.filled(AppConstants.embeddingDimension, 0.0)];
    final classOutput = [List<double>.filled(_labels.length, 0.0)];

    _interpreter.runForMultipleInputs(
      [input],
      {0: embeddingOutput, 1: classOutput},
    );

    final embedding = embeddingOutput[0];
    final probabilities = classOutput[0];

    var bestIndex = 0;
    var bestScore = probabilities[0];
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > bestScore) {
        bestScore = probabilities[i];
        bestIndex = i;
      }
    }

    return ClassificationResult(
      embedding: embedding,
      label: _labels[bestIndex],
      confidence: bestScore,
    );
  }

  List<List<List<double>>> _imageToTensor(img.Image image) {
    return List.generate(_inputSize, (y) {
      return List.generate(_inputSize, (x) {
        final pixel = image.getPixel(x, y);
        return [
          (pixel.r / 127.5) - 1.0,
          (pixel.g / 127.5) - 1.0,
          (pixel.b / 127.5) - 1.0,
        ];
      });
    });
  }

  void close() => _interpreter.close();
}
