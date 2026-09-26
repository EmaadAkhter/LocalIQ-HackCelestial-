"""Time helpers.

Timestamps are stored as **naive UTC**. Keeping them naive avoids the
SQLite-vs-Postgres tz-aware mismatch (SQLite drops tzinfo on read) while staying
unambiguous: the value is always UTC.
"""

from __future__ import annotations

from datetime import datetime, timezone


def utcnow() -> datetime:
    """Current UTC time as a naive datetime."""
    return datetime.now(timezone.utc).replace(tzinfo=None)
