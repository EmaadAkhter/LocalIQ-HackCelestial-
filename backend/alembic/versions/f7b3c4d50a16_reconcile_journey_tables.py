"""Reconcile the PRD v2 tables with the model definitions

Revision ID: f7b3c4d50a16
Revises: e6a2b3d79f45
Create Date: 2026-09-26 20:10:00.000000

``c3d9e1a47b20`` created the journey tables slightly differently from how
``app/models_prd.py`` declares them, which ``test_migrations_match_models``
correctly flags as drift:

* JSON list/dict columns were NOT NULL in the migration but are nullable in the
  models (``sa_column=Column(JSON)``);
* ``badges.code``, ``quests.code``, ``user_progress.user_id`` and
  ``guide_profiles.guide_id`` are unique in the models, so they need unique
  indexes rather than the plain ones that were created;
* ``ix_guide_profiles_verification_tier`` does not exist in the models at all.

This migration brings an already-migrated database in line with the models.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "f7b3c4d50a16"
down_revision: Union[str, None] = "e6a2b3d79f45"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

#: (table, column) pairs that must be nullable, matching the model definitions.
JSON_COLUMNS: list[tuple[str, str]] = [
    ("group_members", "interests"),
    ("group_options", "stops"),
    ("groups", "interests"),
    ("groups", "final_plan"),
    ("meetup_matches", "member_ids"),
    ("meetup_matches", "shared_interests"),
    ("meetup_matches", "plan"),
    ("meetup_requests", "interests"),
    ("quest_runs", "plan"),
    ("quest_runs", "completed_stops"),
    ("quest_runs", "badges_earned"),
    ("user_progress", "badges"),
]

#: Indexes that must be unique because the model marks the column unique.
UNIQUE_INDEXES: list[tuple[str, str, str]] = [
    ("badges", "code", "ix_badges_code"),
    ("quests", "code", "ix_quests_code"),
    ("user_progress", "user_id", "ix_user_progress_user_id"),
    ("guide_profiles", "guide_id", "ix_guide_profiles_guide_id"),
]

#: Index created by c3d9e1a47b20 that the models do not declare.
STRAY_INDEXES: list[tuple[str, str]] = [
    ("guide_profiles", "ix_guide_profiles_verification_tier"),
]


def _indexes(conn, table: str) -> set[str]:
    return {ix["name"] for ix in sa.inspect(conn).get_indexes(table) if ix.get("name")}


def _unique_constraints(conn, table: str) -> set[str]:
    return {
        uc["name"]
        for uc in sa.inspect(conn).get_unique_constraints(table)
        if uc.get("name")
    }


def _is_unique_index(conn, table: str, column: str, index: str) -> bool:
    for ix in sa.inspect(conn).get_indexes(table):
        if ix.get("name") == index and ix.get("unique"):
            return True
    return False


def upgrade() -> None:
    bind = op.get_bind()

    for table, column in JSON_COLUMNS:
        inspector = sa.inspect(bind)
        if table not in inspector.get_table_names():
            continue
        columns = {c["name"]: c for c in inspector.get_columns(table)}
        if column in columns and not columns[column].get("nullable", True):
            with op.batch_alter_table(table) as batch_op:
                batch_op.alter_column(
                    column, existing_type=sa.JSON(), nullable=True
                )

    for table, column, index in UNIQUE_INDEXES:
        names = _indexes(bind, table)
        if index in names and not _is_unique_index(bind, table, column, index):
            op.drop_index(index, table_name=table)
            names = _indexes(bind, table)
        if index not in names:
            op.create_index(index, table, [column], unique=True)

    for table, index in STRAY_INDEXES:
        if index in _indexes(bind, table):
            op.drop_index(index, table_name=table)


def downgrade() -> None:
    bind = op.get_bind()

    for table, index in STRAY_INDEXES:
        if index not in _indexes(bind, table):
            op.create_index(index, table, [index.rsplit("_", 2)[-2]])

    for table, column, index in UNIQUE_INDEXES:
        if _is_unique_index(bind, table, column, index):
            op.drop_index(index, table_name=table)
            op.create_index(index, table, [column], unique=False)

    for table, column in JSON_COLUMNS:
        inspector = sa.inspect(bind)
        if table not in inspector.get_table_names():
            continue
        columns = {c["name"]: c for c in inspector.get_columns(table)}
        if column in columns and columns[column].get("nullable", True):
            with op.batch_alter_table(table) as batch_op:
                batch_op.alter_column(
                    column, existing_type=sa.JSON(), nullable=False
                )
