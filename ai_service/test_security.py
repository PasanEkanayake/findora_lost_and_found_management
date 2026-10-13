"""Tests for security.py. Run:  python -m unittest test_security -v

Works with or without FastAPI installed (a tiny stand-in is used when it isn't,
because only HTTPException and Header are needed).
"""

import os
import sys
import types
import unittest

try:
    import fastapi  # noqa: F401
except ImportError:  # pragma: no cover
    stub = types.ModuleType("fastapi")

    class HTTPException(Exception):
        def __init__(self, status_code, detail=None):
            super().__init__(detail)
            self.status_code = status_code
            self.detail = detail

    stub.HTTPException = HTTPException
    stub.Header = lambda default=None, **kw: default
    sys.modules["fastapi"] = stub

import security  # noqa: E402
from fastapi import HTTPException  # noqa: E402


class SecurityTests(unittest.TestCase):
    def setUp(self):
        security._token_cache.clear()
        security._hits.clear()
        os.environ["SUPABASE_URL"] = "https://example.supabase.co"
        os.environ["SUPABASE_PUBLISHABLE_KEY"] = "pk"
        os.environ["AI_SERVICE_AUTH"] = "required"
        os.environ["RATE_LIMIT_PER_MINUTE"] = "3"
        self.lookups = 0
        security._lookup_user = self._fake_lookup

    def _fake_lookup(self, token):
        self.lookups += 1
        return "user-1" if token == "good" else None

    def status_of(self, header):
        try:
            security.require_user(header)
            return 200
        except HTTPException as exc:
            return exc.status_code

    def test_missing_or_malformed_header_is_401(self):
        self.assertEqual(self.status_of(None), 401)
        self.assertEqual(self.status_of("Basic abc"), 401)
        self.assertEqual(self.status_of("Bearer "), 401)

    def test_invalid_token_is_401(self):
        self.assertEqual(self.status_of("Bearer nope"), 401)

    def test_valid_token_passes_and_is_cached(self):
        self.assertEqual(self.status_of("Bearer good"), 200)
        self.assertEqual(self.status_of("Bearer good"), 200)
        self.assertEqual(self.lookups, 1)  # second call served from the cache

    def test_rate_limit_is_per_person(self):
        for _ in range(3):
            self.assertEqual(self.status_of("Bearer good"), 200)
        self.assertEqual(self.status_of("Bearer good"), 429)

    def test_fails_closed_when_unconfigured(self):
        del os.environ["SUPABASE_URL"]
        self.assertEqual(self.status_of("Bearer good"), 503)

    def test_off_mode_skips_the_check(self):
        os.environ["AI_SERVICE_AUTH"] = "off"
        self.assertEqual(self.status_of(None), 200)

    def test_unknown_mode_is_refused(self):
        os.environ["AI_SERVICE_AUTH"] = "maybe"
        self.assertEqual(self.status_of("Bearer good"), 503)


if __name__ == "__main__":
    unittest.main()
