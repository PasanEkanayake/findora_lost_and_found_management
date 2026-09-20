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
python -m venv .venv
```

Then activate it — this step is genuinely different per OS/shell, unlike
everything else in this README:

```powershell
# Windows, PowerShell (VS Code's default integrated terminal)
.venv\Scripts\Activate.ps1
```
```cmd
:: Windows, Command Prompt
.venv\Scripts\activate.bat
```
```bash
# macOS/Linux, bash/zsh
source .venv/bin/activate
```

If PowerShell refuses to run the `.ps1` script with an "execution
policy" error, that's Windows blocking script execution by default, not
a problem with this project — run this once (per PowerShell session, or
permanently with `-Scope CurrentUser`) and try activating again:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Once activated, your terminal prompt should be prefixed with `(.venv)`.
From here on, every command in this README is identical on every OS:

```bash
pip install -r requirements.txt
# Optional — see "Two install tiers" above:
pip install -r requirements-image.txt
uvicorn main:app --reload
```

First run downloads the sentence-transformer model (~80MB) and NLTK's
tokenizer/stopword/lemmatizer data (plus MobileNetV2, ~14MB, if you
installed the image tier) — subsequent runs use the local cache.

Test it — easiest is just opening this in any browser once the server's
running, which also works identically on every OS:

```
http://localhost:8000/docs
```

That's FastAPI's interactive test page: expand **POST /embed/text**,
click **Try it out**, edit the example JSON, hit **Execute** — no
terminal syntax to get right at all. `http://localhost:8000/health` is
also just a plain URL you can open directly.

Prefer the terminal? The two examples below do the same request, but
their exact syntax is one of the few genuinely OS-specific things left
here — `curl`'s multi-line `\` continuation is bash/zsh syntax that
PowerShell doesn't understand (and PowerShell's own built-in `curl` is
actually an alias for `Invoke-WebRequest`, a different tool with
different flags, which is a common source of confusion — the commands
below sidestep that entirely):

```bash
# macOS/Linux
curl -X POST http://localhost:8000/embed/text \
  -H "Content-Type: application/json" \
  -d '{"title": "Blue Nike backpack", "description": "Left near Gate 3"}'
```
```powershell
# Windows, PowerShell
Invoke-RestMethod -Uri "http://localhost:8000/embed/text" -Method Post `
  -ContentType "application/json" `
  -Body '{"title": "Blue Nike backpack", "description": "Left near Gate 3"}'
```

You should get back `{"embedding": [0.0123, -0.0456, ...]}` — 384 numbers
(PowerShell's `Invoke-RestMethod` prints it slightly differently — an
object you can dig into, e.g. `(...).embedding` — rather than raw JSON,
but the data's the same). `/health` (also just openable in a browser)
reports whether the image tier ended up installed too:
`{"status": "ok", "image_embedding_available": true/false}`.

### Troubleshooting: `ValueError: ... Keras 3 ... not yet supported in Transformers`

Only happens if you installed **both** tiers (`requirements.txt` *and*
`requirements-image.txt`) — not a bug in this project, but a real
incompatibility between `transformers` (a `sentence-transformers`
dependency) and TensorFlow 2.16+'s Keras 3: `transformers` auto-detects
that TensorFlow is installed and tries to wire up TF-specific integration
code that Keras 3 broke, even though nothing here actually needs that
integration (text embedding runs on PyTorch; `image_pipeline.py` talks to
TensorFlow/Keras directly, never through `transformers`).

Already fixed in this repo — both `main.py` and `text_pipeline.py` set
`USE_TF=0` before anything imports `transformers`, which tells it to skip
TensorFlow detection entirely, and the Dockerfiles set the same thing as
a container-wide `ENV`. If you're seeing this anyway (e.g. mid-session
before restarting with the updated files), the fastest unblock is setting
it directly and restarting:

```powershell
# PowerShell
$env:USE_TF = "0"; uvicorn main:app --reload
```
```bash
# bash/zsh
USE_TF=0 uvicorn main:app --reload
```

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

### Testing against a local server instead of deploying

Skip "Deploy it" entirely and just run `uvicorn main:app --reload`
locally (see "Run it locally" above) — but **`AI_SERVICE_URL=http://
localhost:8000` only works if the Flutter app runs on the same machine
as this service**, and it usually doesn't:

- **Physical Android phone over USB** (this project's usual setup —
  see the main README's A6): the phone is a separate device with its
  own `localhost` that isn't your PC. Use your PC's LAN IP instead —
  find it with `ipconfig` (Windows, look for "IPv4 Address") or
  `ifconfig`/`ip addr` (macOS/Linux) — e.g.
  `AI_SERVICE_URL=http://192.168.1.23:8000`. Phone and PC need to be on
  the same Wi-Fi, and Windows Firewall may prompt to allow Python/
  uvicorn through the first time you test it — allow it.
- **Android emulator** on the same PC: emulators alias the host
  machine as `10.0.2.2`, so `AI_SERVICE_URL=http://10.0.2.2:8000` reaches
  a `uvicorn` instance running on your PC directly — no LAN/firewall
  concerns here since it's not leaving the machine.

Either way, remember `.env` is read once at app startup by
`flutter_dotenv` — after changing `AI_SERVICE_URL`, fully restart
(`flutter run` again), a hot reload alone won't pick it up.

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
