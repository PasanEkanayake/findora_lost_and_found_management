# Model assets

Phase 4 (on-device recognition) expects two files here:

- `mobilenet_v2_embedder.tflite` — a pretrained, headless MobileNetV2 (or
  EfficientNet-Lite) model, ideally quantized (int8) to keep the app size
  and inference time down. It should output the penultimate-layer feature
  vector (1280-d for standard MobileNetV2) rather than final ImageNet class
  probabilities, since that vector is what gets compared for similarity
  matching.
- `imagenet_labels.txt` — one label per line, in the order the model's
  classification head expects, used to auto-fill a suggested category.

This folder is intentionally empty otherwise — see `AppConstants` in
`lib/core/constants/app_constants.dart` for the expected file names.
