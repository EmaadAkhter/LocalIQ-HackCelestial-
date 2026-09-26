"""Shared pytest configuration.

Tests must never depend on the developer's local ``.env``: with a real Ollama
model configured, ``/parse`` and ``/chat`` would wait on connection timeouts and
the run would take minutes instead of seconds. Forcing ``APP_ENV=test`` before
any application module is imported also switches rate limiting off, which is
what the rest of the suite assumes.
"""

import os

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("RATE_LIMIT_ENABLED", "false")
