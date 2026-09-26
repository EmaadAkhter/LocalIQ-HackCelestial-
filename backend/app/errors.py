"""Unified error responses and exception handlers.

Every failure leaves the API in the same shape::

    {
      "error": "ValidationError",
      "message": "Request validation failed",
      "request_id": "…",
      "path": "/api/v1/parse",
      "status_code": 422,
      "details": [ … ]        # optional, field-level info
    }
"""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.middleware.request_id import get_request_id

logger = logging.getLogger("localiq.errors")


def error_body(
    request: Request,
    status_code: int,
    error: str,
    message: str,
    details: list | None = None,
) -> dict:
    """Build the canonical error payload."""
    body: dict = {
        "error": error,
        "message": message,
        "request_id": getattr(request.state, "request_id", None) or get_request_id(),
        "path": request.url.path,
        "status_code": status_code,
    }
    if details:
        body["details"] = details
    return body


def error_response(
    request: Request,
    status_code: int,
    error: str,
    message: str,
    headers: dict | None = None,
) -> JSONResponse:
    """Convenience wrapper used outside the handler registration."""
    return JSONResponse(
        status_code=status_code,
        content=error_body(request, status_code, error, message),
        headers=headers,
    )


def register_exception_handlers(app: FastAPI) -> None:
    """Install handlers so no error escapes the unified shape."""

    @app.exception_handler(StarletteHTTPException)
    async def _http_exception(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        detail = exc.detail
        if isinstance(detail, dict):
            # Structured details (e.g. the trust-gate payload) must stay
            # machine-readable instead of being flattened into a string.
            body = error_body(
                request,
                exc.status_code,
                str(detail.get("error") or "HTTPException"),
                str(detail.get("message") or detail),
            )
            body["detail"] = detail
            return JSONResponse(
                status_code=exc.status_code,
                content=body,
                headers=getattr(exc, "headers", None),
            )
        return JSONResponse(
            status_code=exc.status_code,
            content=error_body(request, exc.status_code, "HTTPException", str(detail)),
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_exception(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        details = [
            {
                "loc": list(err.get("loc", [])),
                "msg": err.get("msg", ""),
                "type": err.get("type", ""),
            }
            for err in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content=error_body(request, 422, "ValidationError", "Request validation failed", details),
        )

    @app.exception_handler(Exception)
    async def _unhandled_exception(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled error on %s %s", request.method, request.url.path)
        return JSONResponse(
            status_code=500,
            content=error_body(
                request, 500, "InternalServerError", "An unexpected error occurred"
            ),
        )
