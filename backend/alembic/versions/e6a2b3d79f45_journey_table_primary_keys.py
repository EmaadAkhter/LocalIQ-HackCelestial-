"""Fix the PRD v2 journey tables: add the missing primary keys.

Revision ID: e6a2b3d79f45
Revises: d5f1a2c68e34
Create Date: 2026-09-26 19:05:00.000000

Revision ``c3d9e1a47b20`` created every ``id`` column as a plain NOT NULL
integer without a primary key constraint, so SQLite would not treat it as a
rowid alias and every INSERT failed with "NOT NULL constraint failed".
Alembic's own autogenerate emits ``sa.PrimaryKeyConstraint('id')``; this
migration adds what was missed. SQLite cannot ALTER a column into a primary
key, so the affected tables are rebuilt.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "e6a2b3d79f45"
down_revision: Union[str, None] = "d5f1a2c68e34"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

#: Every table created by c3d9e1a47b20, in an order where children come first so
#: foreign keys stay valid while tables are rebuilt.
TABLES = [
    "mentions",
    "hidden_gem_candidates",
    "sources",
    "badges",
    "user_progress",
    "quest_runs",
    "quest_stops",
    "quests",
    "group_votes",
    "group_options",
    "group_members",
    "groups",
    "meetup_blocks",
    "meetup_reviews",
    "meetup_matches",
    "meetup_requests",
    "guide_trainings",
    "guide_reviews",
    "guide_bookings",
    "guide_availability",
    "guide_profiles",
]


def _has_primary_key(table: str) -> bool:
    """True when ``table`` already declares a primary key.

    ``c3d9e1a47b20`` now creates its ``id`` columns as primary keys, so on a
    fresh database every table is already correct and there is nothing to
    rebuild. This stays tolerant of databases migrated by the earlier, buggy
    revision (notably Postgres, where the missing constraint broke the very
    migration that followed).
    """
    inspector = sa.inspect(op.get_bind())
    try:
        constraint = inspector.get_pk_constraint(table)
    except Exception:  # pragma: no cover - defensive (table missing)
        return True
    return bool(constraint.get("constrained_columns"))


def _rebuild_with_pk(table: str) -> None:
    """Recreate ``table`` with a primary key on ``id`` using batch mode."""
    with op.batch_alter_table(table, recreate="always") as batch_op:
        batch_op.create_primary_key("pk_" + table, ["id"])


def upgrade() -> None:
    for table in TABLES:
        if _has_primary_key(table):
            continue
        _rebuild_with_pk(table)


def downgrade() -> None:
    # The pre-fix state was broken, so there is nothing to restore: leaving the
    # primary keys in place is the only working schema.
    pass
