FROM python:3.11-slim

WORKDIR /app

# See main.py's top for the full explanation: `transformers` (a
# sentence-transformers dependency) auto-detects TensorFlow and wires up
# TF-specific integration code that crashes against TensorFlow's Keras 3
# unless the separate tf-keras shim is installed — which we don't need,
# since text embedding here runs on PyTorch and image_pipeline.py talks
# to TensorFlow directly, never through `transformers`. Set as a
# container-wide ENV (not just in main.py) so it's also in effect for the
# `RUN python -c "from sentence_transformers import ..."` pre-warm step
# below, which would otherwise hit the exact same crash *during the
# image build*, before main.py's own os.environ.setdefault ever runs.
ENV USE_TF=0

# libgl1/libglib2.0-0: OpenCV's imdecode needs these even in the
# "headless" build, since headless only means "no GUI window support", not
# "no image codec dependencies".
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements-image.txt ./
# --default-timeout: a container host's build step can still hit the same
# stalled-read timeout a slow local connection can (see
# requirements-image.txt's comment on tensorflow-cpu's ~390MB wheel) —
# generous here since it only affects build time, not runtime.
RUN pip install --no-cache-dir --default-timeout=1000 -r requirements.txt \
    && pip install --no-cache-dir --default-timeout=1000 -r requirements-image.txt

# Pre-downloads both models at build time rather than on first request, so
# the very first API call after a cold start isn't the one paying a
# multi-hundred-MB download — the tradeoff is a slower image build instead,
# which only happens on deploy, not on every request.
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"
RUN python -c "from tensorflow.keras.applications.mobilenet_v2 import MobileNetV2; MobileNetV2(weights='imagenet', include_top=False, pooling='avg')"
RUN python -c "import nltk; nltk.download('punkt_tab'); nltk.download('stopwords'); nltk.download('wordnet')"

COPY . .

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
