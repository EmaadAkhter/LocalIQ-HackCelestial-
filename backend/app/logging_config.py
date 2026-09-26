"""Structured logging configuration.

Production logs are newline-delimited JSON so they can be shipped and queried.
Every line carries the current ``request_id`` when one is in context. Plain text
is used for local/test runs to keep the console readable.
"""

from __future__ import annotations

import logging
import sys

from pythonjsonlogger.json import JsonFormatter

from app.middleware.request_id import get_request_id

_JSON_FORMAT = "%(asctime)s %(levelname)s %(name)s %(message)s %(request_id)s"
_TEXT_FORMAT = "%(levelname)s %(name)s: %(message)s"

# Uvicorn installs its own handlers; reroute them through ours.
_UVICORN_LOGGERS = ("uvicorn", "uvicorn.error", "uvicorn.access")


class _RequestIDFilter(logging.Filter):
    """Ensure every record has a ``request_id`` field."""

    def filter(self, record: logging.LogRecord) -> bool:
        if not getattr(record, "request_id", None):
            record.request_id = get_request_id()
        return True


def configure_logging(level: str = "INFO", *, json_output: bool = True) -> None:
    """Configure the root logger once, at startup."""
    handler = logging.StreamHandler(sys.stdout)
    handler.addFilter(_RequestIDFilter())
    if json_output:
        handler.setFormatter(
            JsonFormatter(
                _JSON_FORMAT,
                rename_fields={"asctime": "timestamp", "levelname": "level", "name": "logger"},
            )
        )
    else:
        handler.setFormatter(logging.Formatter(_TEXT_FORMAT))

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level.upper())

    for name in _UVICORN_LOGGERS:
        uvicorn_logger = logging.getLogger(name)
        uvicorn_logger.handlers.clear()
        uvicorn_logger.propagate = True
