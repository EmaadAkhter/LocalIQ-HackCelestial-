"""guide request status honest

Revision ID: 7112341e0d86
Revises: 279e5b9c767f
Create Date: 2026-09-27 01:47:02.860970

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7112341e0d86'
down_revision: Union[str, None] = '279e5b9c767f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Rename the placeholder booking status to the request's real state.

    Earlier versions stored every guide request as ``confirmed_mock``, which the
    API echoed back as though a booking had been confirmed. Requests now begin
    life as ``requested``; the model supplies the default for new rows.
    """
    op.execute(
        sa.text(
            "UPDATE guide_requests SET status = 'requested' "
            "WHERE status = 'confirmed_mock'"
        )
    )


def downgrade() -> None:
    op.execute(
        sa.text(
            "UPDATE guide_requests SET status = 'confirmed_mock' "
            "WHERE status = 'requested'"
        )
    )
