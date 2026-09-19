"""Server-side image embedding — TensorFlow/Keras MobileNetV2 with OpenCV
preprocessing.

The app's primary image matching signal comes from the on-device TFLite
model (see lib/core/ml/tflite_classifier.dart and
scripts/export_tflite_model.py, which uses this exact same TensorFlow
MobileNetV2 architecture to produce that .tflite file in the first place).
This endpoint exists for the cases where on-device inference isn't an
option — a future web client with no TFLite runtime, or re-verifying an
embedding server-side — using the full (non-quantized) Keras model instead
of the mobile-optimized export, with OpenCV handling the image
preprocessing rather than Pillow, per this project's documented stack.
"""

from __future__ import annotations

import io
from functools import lru_cache

import cv2
import numpy as np
import tensorflow as tf
from tensorflow.keras.applications.mobilenet_v2 import MobileNetV2, preprocess_input

_INPUT_SIZE = 224  # MobileNetV2's standard input resolution.


@lru_cache(maxsize=1)
def _model() -> tf.keras.Model:
    # include_top=False + pooling="avg": drops the 1000-way ImageNet
    # classification head and instead returns the 1280-d pooled feature
    # vector itself — an *embedding*, not a label, which is what
    # image-similarity matching needs (same shape as item_images.embedding
    # vector(1280) in the SQL schema).
    return MobileNetV2(weights="imagenet", include_top=False, pooling="avg")


def _decode_with_opencv(image_bytes: bytes) -> np.ndarray:
    """Decodes raw image bytes into an RGB array via OpenCV, resized to
    MobileNetV2's expected input. OpenCV decodes as BGR by convention, so
    that channel swap is the one easy-to-miss step here."""
    array = np.frombuffer(image_bytes, dtype=np.uint8)
    bgr = cv2.imdecode(array, cv2.IMREAD_COLOR)
    if bgr is None:
        raise ValueError("Could not decode image data")
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    resized = cv2.resize(rgb, (_INPUT_SIZE, _INPUT_SIZE), interpolation=cv2.INTER_AREA)
    return resized


def embed_image(image_bytes: bytes) -> list[float]:
    image = _decode_with_opencv(image_bytes)
    batch = np.expand_dims(image.astype(np.float32), axis=0)
    batch = preprocess_input(batch)
    embedding = _model().predict(batch, verbose=0)[0]
    return embedding.tolist()
