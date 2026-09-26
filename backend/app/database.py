"""Database configuration for LocalIQ."""

import logging
from collections.abc import Generator
from pathlib import Path

from sqlmodel import Session, SQLModel, create_engine
from sqlalchemy.pool import StaticPool

from app.config import settings

logger = logging.getLogger(__name__)


def _resolve_sqlite_path(database_url: str) -> None:
    """Ensure parent directory exists for file-based SQLite DBs."""
    if database_url.startswith("sqlite:///"):
        # Strip scheme; handle ./ relative paths.
        raw_path = database_url.replace("sqlite:///", "", 1)
        # sqlite:///./data/localiq.db -> ./data/localiq.db
        # sqlite:////abs/path -> //abs/path
        db_path = Path(raw_path)
        if not db_path.is_absolute():
            # Resolve relative to backend/ (this file is backend/app/database.py)
            backend_root = Path(__file__).resolve().parent.parent
            db_path = backend_root / raw_path
        try:
            db_path.parent.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            logger.warning("Could not create SQLite parent dir %s: %s", db_path.parent, exc)


def get_engine():
    """Create database engine with SQLite-safe configuration."""
    database_url = settings.database_url
    try:
        if database_url.startswith("sqlite"):
            _resolve_sqlite_path(database_url)
            engine = create_engine(
                database_url,
                connect_args={"check_same_thread": False},
                poolclass=StaticPool,
                echo=False,
            )
        else:
            engine = create_engine(database_url, echo=False)
        return engine
    except Exception as exc:
        logger.exception("Failed to create database engine: %s", exc)
        raise


engine = get_engine()


def get_session() -> Generator[Session, None, None]:
    """FastAPI dependency yielding a database session."""
    with Session(engine) as session:
        try:
            yield session
        except Exception:
            session.rollback()
            raise


def init_db() -> None:
    """Create tables. Safe to call repeatedly on startup."""
    try:
        # Import models so SQLModel metadata is populated.
        import app.models  # noqa: F401

        SQLModel.metadata.create_all(engine)
        logger.info("Database initialized: %s", settings.database_url)
    except Exception as exc:
        logger.exception("Database initialization failed: %s", exc)
        raise
