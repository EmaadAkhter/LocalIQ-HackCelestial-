"""Cross-database vector column support.

Postgres (with pgvector) stores embeddings as native ``vector``.
SQLite stores them as JSON arrays for local dev/tests. The two formats are
transparently converted at the SQLAlchemy type level.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from sqlalchemy import Dialect, types
from sqlalchemy.dialects.postgresql import JSONB

logger = logging.getLogger(__name__)


try:  # pragma: no cover - optional dependency guarded
    from pgvector.sqlalchemy import Vector as PgVector
except ImportError:  # noqa: F401
    PgVector = None  # type: ignore[misc, assignment]


class Vector(types.TypeDecorator):
    """Vector column that uses pgvector on Postgres and JSON on SQLite."""

    impl = types.JSON
    cache_ok = True

    def __init__(self, dimensions: int = 768) -> None:
        super().__init__()
        self.dimensions = dimensions

    def load_dialect_impl(self, dialect: Dialect) -> Any:
        if dialect.name == "postgresql" and PgVector is not None:
            return dialect.type_descriptor(PgVector(self.dimensions))
        # SQLite / fallback: store as JSON array.
        return dialect.type_descriptor(JSONB if dialect.name == "postgresql" else types.JSON)

    def process_bind_param(self, value: Any | None, dialect: Dialect) -> Any:
        if value is None:
            return None
        if dialect.name == "postgresql" and PgVector is not None:
            # pgvector accepts a list/tuple of floats directly.
            return value
        # SQLite fallback: store JSON string / list.
        if isinstance(value, (list, tuple)):
            return json.dumps([float(v) for v in value])
        return value

    def process_result_value(self, value: Any | None, dialect: Dialect) -> Any:
        if value is None:
            return None
        if isinstance(value, str):
            try:
                return json.loads(value)
            except json.JSONDecodeError:
                logger.warning("Could not decode vector JSON: %s", value[:80])
                return None
        return value
