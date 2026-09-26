"""Request-ID middleware and accessor.

Every request gets a stable trace id: the inbound ``X-Request-ID`` when present
(so ids survive across services and tunnels), otherwise a fresh UUID4. The id is
stored in a ``contextvar`` for log correlation and echoed back in the response
header.
"""

from __future__ import annotations

import uuid
from contextvars import ContextVar

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

REQUEST_ID_HEADER = "X-Request-ID"
_MAX_LEN = 128

_request_id: ContextVar[str] = ContextVar("request_id", default="-")


def get_request_id() -> str:
    """Current request id, or ``-`` outside a request context."""
    return _request_id.get()


class RequestIDMiddleware(BaseHTTPMiddleware):
    """Attach a request id to the context and the response headers."""

    async def dispatch(self, request: Request, call_next) -> Response:
        incoming = (request.headers.get(REQUEST_ID_HEADER) or "").strip()
        request_id = incoming[:_MAX_LEN] if incoming else uuid.uuid4().hex
        token = _request_id.set(request_id)
        request.state.request_id = request_id
        try:
            response = await call_next(request)
        finally:
            _request_id.reset(token)
        response.headers[REQUEST_ID_HEADER] = request_id
        return response
