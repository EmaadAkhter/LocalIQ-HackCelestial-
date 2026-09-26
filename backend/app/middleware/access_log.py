"""Per-request access logging.

Emits one structured log line per request with method, path, status and
duration. Probe paths are skipped so health checks don't flood the log.
"""

from __future__ import annotations

import logging
import time

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.middleware.request_id import get_request_id

logger = logging.getLogger("localiq.access")

_QUIET_PATHS = {"/health", "/healthz", "/readyz", "/metrics"}


class AccessLogMiddleware(BaseHTTPMiddleware):
    """Log each request once, including failures."""

    async def dispatch(self, request: Request, call_next) -> Response:
        start = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            logger.exception(
                "request failed",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": 500,
                    "duration_ms": round((time.perf_counter() - start) * 1000, 2),
                    "request_id": get_request_id(),
                },
            )
            raise

        if request.url.path not in _QUIET_PATHS:
            logger.info(
                "request",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": round((time.perf_counter() - start) * 1000, 2),
                    "request_id": get_request_id(),
                },
            )
        return response
