"""In-memory failed-login lockout.

After ``login_max_attempts`` failures inside a rolling window, an account is
locked for ``login_lockout_minutes``. Successful login clears the counter.

Single-process by design: the self-hosted deployment runs one backend container.
For a multi-replica setup this state must move to Redis.
"""

from __future__ import annotations

import threading
import time

from app.config import get_settings

_lock = threading.Lock()
_failures: dict[str, list[float]] = {}


def _window_seconds() -> int:
    return get_settings().login_lockout_minutes * 60


def _max_attempts() -> int:
    return max(1, get_settings().login_max_attempts)


def _prune(times: list[float], now: float, window: int) -> list[float]:
    return [t for t in times if now - t < window]


def record_failure(key: str) -> None:
    """Record one failed attempt for ``key`` (a normalized email)."""
    now = time.monotonic()
    with _lock:
        times = _prune(_failures.get(key, []), now, _window_seconds())
        times.append(now)
        _failures[key] = times


def clear(key: str) -> None:
    """Clear failures after a successful login."""
    with _lock:
        _failures.pop(key, None)


def locked_for(key: str) -> int:
    """Return seconds remaining in lockout, or 0 when not locked."""
    now = time.monotonic()
    window = _window_seconds()
    with _lock:
        times = _prune(_failures.get(key, []), now, window)
        if len(times) < _max_attempts():
            _failures[key] = times
            return 0
        remaining = window - (now - times[-1])
        if remaining <= 0:
            _failures.pop(key, None)
            return 0
        _failures[key] = times
        return int(remaining) + 1


def reset() -> None:
    """Drop all lockout state (used by tests)."""
    with _lock:
        _failures.clear()
