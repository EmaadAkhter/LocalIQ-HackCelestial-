"""In-app notifications.

Kept separate from the routers so creating one is a plain function call from any
place that has a session — booking transitions, guide approvals, and so on —
without importing HTTP concerns.
"""

from __future__ import annotations

import logging

from sqlmodel import Session, select

from app.models import Notification, NotificationKind
from app.timeutil import utcnow

logger = logging.getLogger(__name__)

#: Notification kinds, re-exported so callers do not import ``app.models``.
BOOKING = NotificationKind.BOOKING.value
GUIDE = NotificationKind.GUIDE.value
SYSTEM = NotificationKind.SYSTEM.value


def create(
    session: Session,
    *,
    user_id: int | None,
    title: str,
    body: str,
    kind: str = SYSTEM,
    data: dict | None = None,
) -> Notification | None:
    """Record a notification for ``user_id``.

    Returns ``None`` and does nothing when ``user_id`` is missing: guide requests
    can be made without signing in, and there is nobody to notify in that case.
    Never raises — a notification is a side effect and must not fail the action
    that triggered it.
    """
    if user_id is None:
        return None
    try:
        row = Notification(
            user_id=user_id,
            kind=kind,
            title=title[:160],
            body=body[:1000],
            data=data or {},
        )
        session.add(row)
        session.commit()
        session.refresh(row)
        return row
    except Exception as exc:  # noqa: BLE001 - notifications must never break a flow
        logger.warning("Could not create notification for user %s: %s", user_id, exc)
        session.rollback()
        return None


def for_user(session: Session, user_id: int, *, limit: int = 50) -> list[Notification]:
    """Newest-first notifications for one user."""
    return list(
        session.exec(
            select(Notification)
            .where(Notification.user_id == user_id)
            .order_by(Notification.created_at.desc(), Notification.id.desc())
            .limit(limit)
        ).all()
    )


def unread_count(session: Session, user_id: int) -> int:
    return len(
        session.exec(
            select(Notification.id).where(
                Notification.user_id == user_id,
                Notification.read_at.is_(None),  # type: ignore[union-attr]
            )
        ).all()
    )


def mark_read(session: Session, notification_id: int, user_id: int) -> bool:
    """Mark one notification read. False when it is missing or not the caller's.

    Scoping the lookup by ``user_id`` means a wrong id returns False rather than
    leaking whether someone else's notification exists.
    """
    row = session.exec(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.user_id == user_id,
        )
    ).first()
    if row is None or row.read_at is not None:
        return False
    row.read_at = utcnow()
    session.add(row)
    session.commit()
    return True


def mark_all_read(session: Session, user_id: int) -> int:
    """Mark every unread notification read. Returns how many changed."""
    rows = session.exec(
        select(Notification).where(
            Notification.user_id == user_id,
            Notification.read_at.is_(None),  # type: ignore[union-attr]
        )
    ).all()
    now = utcnow()
    for row in rows:
        row.read_at = now
        session.add(row)
    session.commit()
    return len(rows)
