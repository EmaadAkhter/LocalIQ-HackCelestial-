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

from app.metrics import REQUEST_DURATION, REQUEST_TOTAL
from app.middleware.request_id import get_request_id

logger = logging.getLogger("localiq.access")

_QUIET_PATHS = {"/health", "/healthz", "/readyz", "/metrics"}


def _route_label(request: Request) -> str:
    """Use the route template to keep metric cardinality low."""
    route = request.scope.get("route")
    return getattr(route, "path", None) or "unmatched"


class AccessLogMiddleware(BaseHTTPMiddleware):
    """Log each request once and record Prometheus metrics."""

    async def dispatch(self, request: Request, call_next) -> Response:
        start = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            duration = time.perf_counter() - start
            REQUEST_TOTAL.labels(request.method, _route_label(request), "500").inc()
            REQUEST_DURATION.labels(request.method, _route_label(request)).observe(duration)
            logger.exception(
                "request failed",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": 500,
                    "duration_ms": round(duration * 1000, 2),
                    "request_id": get_request_id(),
                },
            )
            raise

        duration = time.perf_counter() - start
        path_label = _route_label(request)
        REQUEST_TOTAL.labels(request.method, path_label, str(response.status_code)).inc()
        REQUEST_DURATION.labels(request.method, path_label).observe(duration)

        if request.url.path not in _QUIET_PATHS:
            logger.info(
                "request",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": round(duration * 1000, 2),
                    "request_id": get_request_id(),
                },
            )
        return response
