"""Text preprocessing (NLTK) + sentence embedding (Sentence-Transformers)
for the NLP side of Findora's multimodal matching — see
supabase/05_multimodal_matching.sql for how the resulting vector is used
(compared via pgvector cosine distance against other items' embeddings).

Why preprocess before embedding at all, given sentence-transformers models
are usually applied to raw text: item titles/descriptions are short and
inconsistent ("Blue Nike backpack!!", "found - blue backpack near gate 3")
— stripping punctuation noise and stopwords, and lemmatizing, reduces two
people's independently-worded descriptions of the same object to a more
comparable form before they ever reach the model. It's a small effect on a
model this size, but a deliberate one, and it's the NLTK part of the
"TensorFlow, OpenCV, Sentence Transformers, NLTK" stack this app documents.
"""

from __future__ import annotations

import os

# See main.py's identical line for the full explanation — repeated here
# (setdefault, so whichever of these two runs first "wins" and the other
# is a harmless no-op) so this module is also safe to import directly
# (e.g. `python text_pipeline.py`, or a standalone test) without going
# through main.py first.
os.environ.setdefault("USE_TF", "0")

import re
import string
from functools import lru_cache

import nltk
from nltk.corpus import stopwords
from nltk.stem import WordNetLemmatizer
from nltk.tokenize import word_tokenize
from sentence_transformers import SentenceTransformer

# Downloaded once at container build time (see Dockerfile) — checked again
# here (quietly, and cheaply once cached) so `python text_pipeline.py` or a
# test run outside Docker still works without a manual setup step.
for _resource in ("tokenizers/punkt_tab", "corpora/stopwords", "corpora/wordnet"):
    try:
        nltk.data.find(_resource)
    except LookupError:
        nltk.download(_resource.split("/")[-1], quiet=True)

_STOPWORDS = set(stopwords.words("english"))
_LEMMATIZER = WordNetLemmatizer()
_PUNCT_TABLE = str.maketrans("", "", string.punctuation)

# all-MiniLM-L6-v2: 384-dimensional output (matches items.text_embedding's
# vector(384) column in the SQL migration), ~80MB, and fast enough to run
# comfortably on a free-tier CPU instance — a larger model would be more
# accurate but isn't worth the cold-start latency for short item
# descriptions like these.
_MODEL_NAME = "all-MiniLM-L6-v2"


@lru_cache(maxsize=1)
def _model() -> SentenceTransformer:
    # Loaded lazily and cached rather than at import time, so importing
    # this module (e.g. from a test) doesn't force a model download.
    return SentenceTransformer(_MODEL_NAME)


def clean_text(raw: str) -> str:
    """Lowercase, strip punctuation/extra whitespace, drop stopwords, and
    lemmatize — turns e.g. "Found!! Blue backpacks near the Gates" into
    "found blue backpack near gate"."""
    lowered = raw.lower().translate(_PUNCT_TABLE)
    lowered = re.sub(r"\s+", " ", lowered).strip()
    tokens = word_tokenize(lowered)
    kept = [_LEMMATIZER.lemmatize(t) for t in tokens if t not in _STOPWORDS and t.isalpha()]
    return " ".join(kept)


def embed_item_text(title: str, description: str = "") -> list[float]:
    """Combines title + description (title carries more signal for a short
    report, so it's repeated to weight it slightly higher) into one
    embedding representing "what this item is"."""
    combined = f"{title}. {title}. {description}".strip()
    cleaned = clean_text(combined)
    if not cleaned:
        # Degenerate input (e.g. title was just emoji/punctuation) — fall
        # back to the raw text rather than embedding an empty string.
        cleaned = combined
    embedding = _model().encode(cleaned, normalize_embeddings=True)
    return embedding.tolist()
