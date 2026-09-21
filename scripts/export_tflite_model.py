"""
Exports a MobileNetV2 model (pretrained on ImageNet) to TensorFlow Lite,
producing two outputs from a single forward pass:

  0: a 1280-d embedding (the pooled feature vector used for AI matching)
  1: a 1000-way ImageNet classification (used to auto-suggest a category)

Run this on your own machine, not in a restricted sandbox — it downloads
~14MB of pretrained weights plus a small label-index file from TensorFlow's
servers.

Usage:
    pip install -r requirements.txt
    python export_tflite_model.py

Writes straight into the Flutter project's assets/models/ folder — no
separate copy step, on purpose: that used to be a real trap. Both output
files would land in this scripts/ folder, the script's own printout would
say "copy both into assets/models/", and it was easy to run the script
successfully, see no errors, and never do that last step — leaving
assets/models/ still empty and AI matching silently never working, with
nothing to indicate why. Writing directly to the real destination removes
that whole failure mode.
"""

import json
from pathlib import Path

import tensorflow as tf

# scripts/export_tflite_model.py -> ../assets/models/
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "models"


def build_combined_model() -> tf.keras.Model:
    """Wraps MobileNetV2 so a single forward pass returns both the pooled
    embedding and the full ImageNet classification, sharing one
    convolutional pass and one set of pretrained weights."""
    full_model = tf.keras.applications.MobileNetV2(weights="imagenet", include_top=True)

    # The layer feeding the final Dense(1000) is the 1280-d embedding used
    # for similarity matching. Look it up by name first; fall back to
    # searching by output shape in case a TF version renames it.
    try:
        embedding_layer = full_model.get_layer("global_average_pooling2d")
    except ValueError:
        embedding_layer = next(
            layer
            for layer in full_model.layers
            if tuple(layer.output_shape) == (None, 1280)
        )

    return tf.keras.Model(
        inputs=full_model.input,
        outputs=[embedding_layer.output, full_model.output],
    )


def export_labels(path: Path) -> None:
    """Writes one ImageNet label per line, in the exact index order the
    model's classification output uses. Generated from Keras's own class
    index file rather than hand-typed, so it can't drift out of sync with
    the model's actual output order."""
    class_index_path = tf.keras.utils.get_file(
        "imagenet_class_index.json",
        "https://storage.googleapis.com/download.tensorflow.org/data/imagenet_class_index.json",
    )
    with open(class_index_path) as f:
        class_index = json.load(f)

    # class_index maps "0".."999" -> [wordnet_id, human_readable_label]
    labels = [class_index[str(i)][1] for i in range(len(class_index))]
    path.write_text("\n".join(labels))


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    model = build_combined_model()

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    # Dynamic range quantization: shrinks the file substantially by
    # quantizing weights to int8, while keeping input/output tensors as
    # float32 — so no representative dataset is needed and the Dart-side
    # preprocessing code in tflite_classifier.dart doesn't have to change.
    # Comment this line out for a plain float32 export if you'd rather
    # trade file size for simplicity/max accuracy.
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    tflite_model = converter.convert()
    model_path = OUTPUT_DIR / "mobilenet_v2_embedder.tflite"
    model_path.write_bytes(tflite_model)

    export_labels(OUTPUT_DIR / "imagenet_labels.txt")

    # tflite_classifier.dart assumes output index 0 = embedding, index 1 =
    # classification. The converter *should* preserve the Keras outputs
    # list order, but double-check the printout below against that
    # assumption before shipping — swap the indices in classify() if not.
    interpreter = tf.lite.Interpreter(model_content=tflite_model)
    interpreter.allocate_tensors()
    print("Output tensor order (verify this matches tflite_classifier.dart):")
    for i, detail in enumerate(interpreter.get_output_details()):
        print(f"  index {i}: shape={detail['shape']}, name={detail['name']}")

    print(f"\nDone. Wrote both files directly to {OUTPUT_DIR} — nothing left to copy.")


if __name__ == "__main__":
    main()

