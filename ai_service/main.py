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

Security: every /embed call needs the caller's Supabase sign-in token and is
rate limited per person (see security.py for the environment variables to set —
SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are REQUIRED unless AI_SERVICE_AUTH=off,
which is for local development only).

Deploy: any container host works (Render, Railway, Fly.io, Cloud Run) —
see README.md in this folder for the walkthrough and for wiring the
deployed URL into the Flutter app via AUTH_CALLBACK_URL's sibling env var,
AI_SERVICE_URL.
"""

from __future__ import annotations

import os

# Must run before anything imports `transformers` (sentence-transformers'
# dependency, imported by text_pipeline below) — `transformers` probes
# whether TensorFlow is importable and, if so, eagerly wires up its TF
# integration classes, which on a modern TensorFlow (Keras 3 by default
# since TF 2.16) crashes with "Your currently installed version of Keras
# is Keras 3, but this is not yet supported in Transformers" unless the
# separate `tf-keras` compatibility shim is also installed. We don't need
# any of that: text embedding here runs on PyTorch (sentence-transformers'
# default backend), and image_pipeline.py talks to TensorFlow/Keras
# directly, never through `transformers`. Setting USE_TF=0 tells
# `transformers` to skip TF detection/integration entirely, so it's a
# non-issue regardless of whether TensorFlow happens to also be installed
# (e.g. from requirements-image.txt) in the same environment.
# `setdefault` rather than a plain assignment so an operator who
# deliberately wants this on can still override it via their own shell
# env or the container's env before launch.
os.environ.setdefault("USE_TF", "0")

from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import text_pipeline
from security import require_user

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

# CORS: the Android app is not a browser and needs none of this. Browsers are
# only let in from origins you list explicitly (CORS_ORIGINS, comma separated —
# e.g. a Flutter web build). Default: none.
_cors_origins = [o.strip() for o in os.environ.get("CORS_ORIGINS", "").split(",") if o.strip()]
if _cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_cors_origins,
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type"],
    )

# Largest photo accepted by /embed/image.
MAX_IMAGE_BYTES = 10 * 1024 * 1024


class EmbedTextRequest(BaseModel):
    # Same limits as the database (items.title <= 120, description <= 2000),
    # with a little headroom.
    title: str = Field(max_length=200)
    description: str = Field(default="", max_length=4000)


class EmbedTextResponse(BaseModel):
    embedding: list[float]


class EmbedImageResponse(BaseModel):
    embedding: list[float]


@app.get("/health")
def health() -> dict[str, object]:
    return {"status": "ok", "image_embedding_available": image_pipeline is not None}


@app.post("/embed/text", response_model=EmbedTextResponse)
def embed_text(
    payload: EmbedTextRequest, _user: str = Depends(require_user)
) -> EmbedTextResponse:
    if not payload.title.strip() and not payload.description.strip():
        raise HTTPException(400, "title or description is required")
    embedding = text_pipeline.embed_item_text(payload.title, payload.description)
    return EmbedTextResponse(embedding=embedding)


@app.post("/embed/image", response_model=EmbedImageResponse)
async def embed_image(
    file: UploadFile = File(...), _user: str = Depends(require_user)
) -> EmbedImageResponse:
    if image_pipeline is None:
        raise HTTPException(
            501,
            "Image embedding isn't installed on this deployment. Install "
            "requirements-image.txt (adds TensorFlow + OpenCV) and restart "
            f"the service. Import error was: {_image_pipeline_import_error}",
        )
    # Read one byte past the cap so an oversized upload is detected without
    # ever holding more than MAX_IMAGE_BYTES + 1 in memory.
    image_bytes = await file.read(MAX_IMAGE_BYTES + 1)
    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "photo is too large (10 MB maximum)")
    if not image_bytes:
        raise HTTPException(400, "empty file")
    try:
        embedding = image_pipeline.embed_image(image_bytes)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return EmbedImageResponse(embedding=embedding)
