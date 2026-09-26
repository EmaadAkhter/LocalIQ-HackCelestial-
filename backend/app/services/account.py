"""Account deletion.

Erasing an account has to reach every table that references the user, or the
"deleted" account leaves orphaned personal data behind. Rather than maintain a
list that silently rots whenever a model is added, this walks the SQLModel
metadata and clears each column that points at ``users.id``.

Tables are visited in reverse dependency order so foreign keys stay satisfied
(children before parents), and the user row itself is deleted by the caller
after the sweep.
"""

from __future__ import annotations

import logging

from sqlmodel import Session, SQLModel

logger = logging.getLogger(__name__)

#: Columns across the schema that reference ``users.id``. ``user_id`` covers the
#: majority of tables; the rest are the social / moderation edges added by the
#: PRD models (blocks, group ownership, review authorship, candidate triage).
USER_REFERENCE_COLUMNS = (
    "user_id",
    "owner_id",
    "blocker_id",
    "blocked_id",
    "submitted_by",
    "reviewed_by",
)


def purge_user_rows(session: Session, user_id: int) -> int:
    """Delete every row referencing ``user_id``, except the user row itself.

    Returns the number of rows removed so the caller can log it. The caller is
    responsible for deleting the ``users`` row afterwards.
    """
    removed = 0
    # Reverse dependency order: dependents before the tables they point at.
    for table in reversed(SQLModel.metadata.sorted_tables):
        for column in USER_REFERENCE_COLUMNS:
            if column not in table.columns:
                continue
            result = session.execute(table.delete().where(table.c[column] == user_id))
            removed += result.rowcount or 0
    session.commit()
    return removed
