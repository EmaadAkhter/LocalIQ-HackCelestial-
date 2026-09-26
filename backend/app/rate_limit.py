"""Rate limiting via slowapi.

Limits are per client IP. The global default covers ordinary reads; the LLM and
auth routes get tighter limits attached with ``@limiter.limit(...)``.

The limiter is disabled automatically in the test environment (see
``Settings.rate_limiting_on``) so the suite is not throttled.
"""

from __future__ import annotations

from slowapi import Limiter
from slowapi.util import get_remote_address

from app.config import get_settings

PUBLIC_LIMIT = "60/minute"
RECOMMEND_LIMIT = "30/minute"
LLM_LIMIT = "20/minute"
AUTH_LIMIT = "10/minute"


def create_limiter(*, enabled: bool = True) -> Limiter:
    """Build a limiter. Exposed as a factory so tests can build their own.

    Limits are attached with ``@limiter.limit(...)`` on each route rather than
    ``default_limits`` + ``SlowAPIMiddleware``: this FastAPI version wraps
    routers in lazy ``_IncludedRouter`` objects, so the middleware cannot
    discover route handlers and its default limits silently no-op.
    """
    return Limiter(
        key_func=get_remote_address,
        default_limits=[],
        enabled=enabled,
        headers_enabled=True,
    )


limiter = create_limiter(enabled=get_settings().rate_limiting_on)
