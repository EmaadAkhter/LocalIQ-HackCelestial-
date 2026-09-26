"""Database configuration for LocalIQ."""

import logging
from collections.abc import Generator
from pathlib import Path

from sqlmodel import Session, SQLModel, create_engine
from sqlalchemy.pool import StaticPool

from app.config import settings

logger = logging.getLogger(__name__)

# Everything relative in the config is resolved against the backend package root
# so behaviour does not depend on the current working directory.
BACKEND_ROOT = Path(__file__).resolve().parent.parent


def _absolute_sqlite_url(database_url: str) -> str:
    """Resolve a file-based SQLite URL to an absolute path.

    ``sqlite:///./data/localiq.db`` is relative to the *current working
    directory*, which differs between ``uvicorn`` (run from ``backend/``),
    Docker (WORKDIR ``/app``) and pytest. Resolving it once against the backend
    root keeps the directory that gets created and the file that gets opened in
    the same place, whatever the cwd is.
    """
    if not database_url.startswith("sqlite"):
        return database_url
    # In-memory SQLite is used by tests; leave it untouched.
    raw_path = database_url.split("sqlite:///", 1)[-1]
    if not raw_path or ":memory:" in raw_path or raw_path.startswith(":memory:"):
        return database_url
    db_path = Path(raw_path)
    if not db_path.is_absolute():
        db_path = (BACKEND_ROOT / raw_path).resolve()
    try:
        db_path.parent.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        logger.warning("Could not create SQLite parent dir %s: %s", db_path.parent, exc)
    return f"sqlite:///{db_path.as_posix()}"


def get_engine():
    """Create database engine with SQLite-safe configuration."""
    database_url = _absolute_sqlite_url(settings.database_url)
    try:
        if database_url.startswith("sqlite"):
            engine = create_engine(
                database_url,
                connect_args={"check_same_thread": False},
                poolclass=StaticPool,
                echo=False,
            )
        else:
            engine = create_engine(
                database_url,
                echo=False,
                pool_size=settings.db_pool_size,
                max_overflow=settings.db_max_overflow,
                pool_recycle=settings.db_pool_recycle_seconds,
                # Reconnect transparently if the DB dropped an idle connection.
                pool_pre_ping=True,
            )
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
        # Import models so SQLModel metadata is populated. Both modules are
        # required: PRD v2 journey tables live in app.models_prd.
        import app.models  # noqa: F401
        import app.models_prd  # noqa: F401

        SQLModel.metadata.create_all(engine)
        logger.info("Database initialized: %s", settings.database_url)
    except Exception as exc:
        logger.exception("Database initialization failed: %s", exc)
        raise
