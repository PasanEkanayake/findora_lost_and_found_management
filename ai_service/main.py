"""Findora AI matching microservice.

Optional infrastructure — see lib/core/ml/text_embedding_service.dart's
doc comment for how the Flutter app treats this service being unset,
unreachable, or slow: never as an error, always as "skip this signal for
now". Nothing in the core app (posting an item, browsing, image-based
matching) depends on this being deployed.

Endpoints:
  GET  /health        - liveness check
  POST /embed/text     - title + description -> 384-d sentence embedding
                          (text_pipeline.py: NLTK + Sentence-Transformers)
  POST /embed/image     - photo bytes -> 1280-d image embedding
                          (image_pipeline.py: OpenCV + TensorFlow/Keras)

Run locally:
    pip install -r requirements.txt
    uvicorn main:app --reload

/embed/image needs an extra, heavier install — see requirements-image.txt
and this folder's README ("Two install tiers"). Without it, /embed/text
(the endpoint the app actually uses) still works fully; /embed/image
responds with a clear 501 instead of crashing the whole service on
startup.

Deploy: any container host works (Render, Railway, Fly.io, Cloud Run) —
see README.md in this folder for the walkthrough and for wiring the
deployed URL into the Flutter app via AUTH_CALLBACK_URL's sibling env var,
AI_SERVICE_URL.
"""

from __future__ import annotations

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import text_pipeline

# image_pipeline imports tensorflow + cv2, both only in
# requirements-image.txt (not requirements.txt). Importing it
# unconditionally and letting a missing-dependency ImportError propagate
# would mean the *entire* service, including /embed/text, refuses to
# start for anyone who only installed the core requirements — so the
# import is attempted here but wrapped in try/except, and /embed/image
# below checks `image_pipeline is None` before using it. That confines a
# missing TensorFlow/OpenCV install to just that one endpoint returning a
# clear 501, instead of the whole process failing to boot.
_image_pipeline_import_error: Exception | None = None
try:
    import image_pipeline
except ImportError as exc:  # pragma: no cover - exercised by missing-deps setups
    image_pipeline = None  # type: ignore[assignment]
    _image_pipeline_import_error = exc

app = FastAPI(title="Findora AI Matching Service", version="1.0.0")

# Wide open on purpose: every request here is either an item's own
# title/description (about to be public in the feed anyway) or an item
# photo, and the only client calling this is Findora itself — there's no
# session/auth data in play for a browser-based (Flutter web) build to
# leak cross-origin. Tighten this to your deployed app's origin(s) if
# you'd rather be explicit.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class EmbedTextRequest(BaseModel):
    title: str
    description: str = ""


class EmbedTextResponse(BaseModel):
    embedding: list[float]


class EmbedImageResponse(BaseModel):
    embedding: list[float]


@app.get("/health")
def health() -> dict[str, object]:
    return {"status": "ok", "image_embedding_available": image_pipeline is not None}


@app.post("/embed/text", response_model=EmbedTextResponse)
def embed_text(payload: EmbedTextRequest) -> EmbedTextResponse:
    if not payload.title.strip() and not payload.description.strip():
        raise HTTPException(400, "title or description is required")
    embedding = text_pipeline.embed_item_text(payload.title, payload.description)
    return EmbedTextResponse(embedding=embedding)


@app.post("/embed/image", response_model=EmbedImageResponse)
async def embed_image(file: UploadFile = File(...)) -> EmbedImageResponse:
    if image_pipeline is None:
        raise HTTPException(
            501,
            "Image embedding isn't installed on this deployment. Install "
            "requirements-image.txt (adds TensorFlow + OpenCV) and restart "
            f"the service. Import error was: {_image_pipeline_import_error}",
        )
    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(400, "empty file")
    try:
        embedding = image_pipeline.embed_image(image_bytes)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return EmbedImageResponse(embedding=embedding)
