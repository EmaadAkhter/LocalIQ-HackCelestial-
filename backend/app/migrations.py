"""Programmatic Alembic runner.

Called on startup so containers and K8s pods apply pending migrations before
serving. The database URL comes from ``app.config.settings`` via ``alembic/env.py``.
"""

from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.config import Config

_BACKEND_ROOT = Path(__file__).resolve().parent.parent


def _alembic_config() -> Config:
    config = Config(str(_BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
    return config


def upgrade_to_head() -> None:
    """Apply every pending migration."""
    command.upgrade(_alembic_config(), "head")
