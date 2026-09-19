# Findora AI matching microservice

Optional. The app works fully without this — image-based matching runs
entirely on-device (see `lib/core/ml/tflite_classifier.dart`) and doesn't
need it. This service adds the **text/NLP** matching signal (and an
optional server-side image embedding endpoint) described in
`supabase/05_multimodal_matching.sql`.

**Stack**: FastAPI · Sentence-Transformers (`all-MiniLM-L6-v2`) · NLTK ·
TensorFlow/Keras (`MobileNetV2`) · OpenCV.

## Two install tiers

Only `/embed/text` is actually called by the app right now (see
"`/embed/image` — why it exists but isn't called yet" below) — so its
dependencies are split into two files, and you only need the second one
if you specifically want `/embed/image` working too:

- **`requirements.txt`** — FastAPI, Sentence-Transformers, NLTK. Tens of
  MB total. Everything `/embed/text` needs.
- **`requirements-image.txt`** — TensorFlow-CPU + OpenCV, only for
  `/embed/image`. `tensorflow-cpu` alone is a ~390MB wheel, which is
  the usual culprit if a `pip install` here times out on a slow or
  throttled connection (a corporate network, mobile hotspot, etc.) —
  pip's default per-read timeout can trip on a connection slow enough
  that an individual chunk stalls past it, even though the download
  would otherwise complete fine given more time. If that happens:
  ```bash
  pip install --default-timeout=1000 -r requirements-image.txt
  ```
  pip resumes using what it already downloaded rather than starting
  over, so a second attempt after a timeout is usually much faster.
  Still timing out repeatedly? Skip it — running with just
  `requirements.txt` installed is a fully supported, permanent setup,
  not just a fallback: `/embed/text` (and therefore all of this
  project's actual text-matching feature) works completely without
  `requirements-image.txt` ever being installed. `/embed/image` just
  returns a clear `501` explaining it's not installed, instead of the
  service failing to start — see `main.py`'s guarded import of
  `image_pipeline`.

## Run it locally

```bash
cd ai_service
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# Optional — see "Two install tiers" above:
pip install -r requirements-image.txt
uvicorn main:app --reload
```

First run downloads the sentence-transformer model (~80MB) and NLTK's
tokenizer/stopword/lemmatizer data (plus MobileNetV2, ~14MB, if you
installed the image tier) — subsequent runs use the local cache.

Test it:

```bash
curl -X POST http://localhost:8000/embed/text \
  -H "Content-Type: application/json" \
  -d '{"title": "Blue Nike backpack", "description": "Left near Gate 3"}'
```

You should get back `{"embedding": [0.0123, -0.0456, ...]}` — 384 numbers.
`curl http://localhost:8000/health` also reports whether the image tier
ended up installed (`"image_embedding_available": true/false`).

## Deploy it

Any container host works. Render's free tier is the least setup for a
side project:

1. Push this repo (or just the `ai_service/` folder) to GitHub.
2. Render → **New → Web Service** → connect the repo.
3. **Root directory**: `ai_service`. Render auto-detects `Dockerfile`,
   which installs both tiers (so `/embed/image` works too). If you'd
   rather deploy a smaller, faster-building image with just
   `/embed/text` — the one the app actually uses — point Render at
   `Dockerfile.text-only` instead (Advanced → Dockerfile Path).
4. **Instance type**: free tier works, but expect ~30–60s cold starts
   after idling — `TextEmbeddingService`'s 6-second client-side timeout
   (see that file) is tuned around that being an acceptable "matching
   just skips the text signal this time" outcome, not a hang.
5. Deploy, then copy the service's URL (`https://your-service.onrender.com`).

Railway, Fly.io, and Google Cloud Run all work the same way — point them
at whichever Dockerfile you want.

## Wire it into the app

Set `AI_SERVICE_URL` in `.env` (see `.env.example`) to the deployed URL,
**no trailing slash**:

```
AI_SERVICE_URL=https://your-service.onrender.com
```

That's it — `ItemsRepository.createItem` (via
`TextEmbeddingService.tryEmbed`) starts calling `/embed/text` on every new
post, and `supabase/05_multimodal_matching.sql`'s trigger picks up the
stored embedding automatically.

## Why NLTK preprocessing before an already-pretrained embedding model

See the docstring at the top of `text_pipeline.py` — short version:
item titles/descriptions are noisy and inconsistently worded ("Blue Nike
backpack!!" vs "found - blue backpack near gate 3"), so cleaning and
lemmatizing first nudges two independent descriptions of the same object
closer together before they reach the model.

## `/embed/image` — why it exists but isn't called yet

The Flutter app's image matching already runs on-device via TFLite (the
same MobileNetV2 architecture `image_pipeline.py` uses here, just the
full Keras model instead of the mobile-optimized export — see
`scripts/export_tflite_model.py`). This endpoint is here for whenever a
client without on-device inference needs the same embedding server-side
(a hypothetical Flutter web build, most likely) — wire it up the same way
`/embed/text` is wired up if/when that's needed.
