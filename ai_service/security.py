"""Access control for the Findora AI service: who may call it, and how often.

Why this exists: the service does real compute (a sentence-transformer, optionally
TensorFlow) on request and was open to the whole internet — anyone who found the
URL could run it up. Now every /embed call must carry the caller's Supabase
sign-in token, and each person is rate limited.

How a token is checked: by asking Supabase itself (GET {SUPABASE_URL}/auth/v1/user).
That works whichever way your project signs tokens (legacy shared secret or the
newer asymmetric keys) and needs no secret on this service — only the project URL
and the *publishable* key, both of which are public anyway. A successful check is
remembered for a few minutes so a burst of requests costs one lookup.

Configuration (environment variables):
  SUPABASE_URL              your project URL, e.g. https://xyz.supabase.co  (required)
  SUPABASE_PUBLISHABLE_KEY  the publishable/anon key                         (required)
  AI_SERVICE_AUTH           "required" (default) or "off". "off" skips the check
                            entirely — for running locally only, never in production.
  RATE_LIMIT_PER_MINUTE     requests per person per minute across /embed/* (default 30)

If auth is "required" but SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY are missing, every
/embed call is refused with 503 (the service fails closed rather than open).
"""

from __future__ import annotations

import hashlib
import json
import os
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict, deque

from fastapi import Header, HTTPException

_CACHE_SECONDS = 300
_token_cache: dict[str, tuple[float, str]] = {}  # sha256(token) -> (expires_at, user_id)
_cache_lock = threading.Lock()

_hits: dict[str, deque[float]] = defaultdict(deque)  # user_id -> recent request times
_hits_lock = threading.Lock()


def _auth_mode() -> str:
    return os.environ.get("AI_SERVICE_AUTH", "required").strip().lower()


def _lookup_user(token: str) -> str | None:
    """Ask Supabase who this token belongs to. Returns the user id, or None if invalid."""
    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
    request = urllib.request.Request(
        f"{base}/auth/v1/user",
        headers={"Authorization": f"Bearer {token}", "apikey": key},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            body = json.loads(response.read().decode("utf-8"))
            return body.get("id")
    except urllib.error.HTTPError as exc:
        if exc.code in (400, 401, 403):
            return None
        raise HTTPException(503, "Could not verify your sign-in right now.") from exc
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        raise HTTPException(503, "Could not verify your sign-in right now.") from exc


def require_user(authorization: str | None = Header(default=None)) -> str:
    """FastAPI dependency: returns the caller's user id, or raises 401/429/503."""
    mode = _auth_mode()
    if mode == "off":
        return "anonymous"
    if mode != "required":
        raise HTTPException(503, "AI_SERVICE_AUTH must be 'required' or 'off'.")

    if not os.environ.get("SUPABASE_URL") or not os.environ.get("SUPABASE_PUBLISHABLE_KEY"):
        raise HTTPException(503, "Service is not configured (SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY).")

    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Sign in required.")
    token = authorization[7:].strip()
    if not token:
        raise HTTPException(401, "Sign in required.")

    fingerprint = hashlib.sha256(token.encode("utf-8")).hexdigest()
    now = time.time()
    user_id: str | None = None
    with _cache_lock:
        cached = _token_cache.get(fingerprint)
        if cached and cached[0] > now:
            user_id = cached[1]

    if user_id is None:
        user_id = _lookup_user(token)
        if user_id is None:
            raise HTTPException(401, "Invalid or expired sign-in.")
        with _cache_lock:
            if len(_token_cache) > 5000:  # keep memory bounded
                _token_cache.clear()
            _token_cache[fingerprint] = (now + _CACHE_SECONDS, user_id)

    _enforce_rate_limit(user_id, now)
    return user_id


def _enforce_rate_limit(user_id: str, now: float) -> None:
    limit = int(os.environ.get("RATE_LIMIT_PER_MINUTE", "30"))
    with _hits_lock:
        window = _hits[user_id]
        while window and window[0] <= now - 60:
            window.popleft()
        if len(window) >= limit:
            raise HTTPException(429, "Too many requests. Please wait a moment.")
        window.append(now)
        if len(_hits) > 5000:  # drop idle users so the table can't grow forever
            for key in [k for k, v in _hits.items() if not v]:
                _hits.pop(key, None)
