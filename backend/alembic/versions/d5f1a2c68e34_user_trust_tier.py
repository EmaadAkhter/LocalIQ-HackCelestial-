"""PRD v2 traveller trust tier columns

Revision ID: d5f1a2c68e34
Revises: c3d9e1a47b20
Create Date: 2026-09-26 18:40:00.000000

Adds ``users.trust_tier`` / ``users.trust_verified_at`` so the meetup and group
trust gates have server-side state to read. Additive only: existing users get
the ``basic`` default and no rows are rewritten.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "d5f1a2c68e34"
down_revision: Union[str, None] = "c3d9e1a47b20"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(conn, table: str, column: str) -> bool:
    inspector = sa.inspect(conn)
    if table not in inspector.get_table_names():
        return False
    return column in {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    bind = op.get_bind()
    if not _has_column(bind, "users", "trust_tier"):
        op.add_column(
            "users",
            sa.Column("trust_tier", sa.String(), nullable=False, server_default="basic"),
        )
        op.create_index("ix_users_trust_tier", "users", ["trust_tier"])
    if not _has_column(bind, "users", "trust_verified_at"):
        op.add_column(
            "users",
            sa.Column("trust_verified_at", sa.DateTime(), nullable=True),
        )


def downgrade() -> None:
    op.drop_index("ix_users_trust_tier", table_name="users")
    op.drop_column("users", "trust_verified_at")
    op.drop_column("users", "trust_tier")
