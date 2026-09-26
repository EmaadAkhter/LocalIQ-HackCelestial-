"""In-app notifications.

Every route is scoped to the authenticated user, so a client can never read or
mutate another account's notifications by passing an id.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlmodel import Session

from app.database import get_session
from app.models import User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import NotificationResponse
from app.services import notifications as notification_service
from app.services.auth import get_current_user

router = APIRouter()


@router.get(
    "/notifications",
    response_model=list[NotificationResponse],
    summary="My notifications",
)
@limiter.limit(PUBLIC_LIMIT)
def list_notifications(
    request: Request,
    response: Response,
    limit: int = 50,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Newest first. ``limit`` is clamped so it cannot be used to bulk-dump."""
    return notification_service.for_user(
        session, current_user.id, limit=min(max(limit, 1), 200)  # type: ignore[arg-type]
    )


@router.get("/notifications/unread-count", summary="Unread notification count")
@limiter.limit(PUBLIC_LIMIT)
def unread_count(
    request: Request,
    response: Response,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return {"unread": notification_service.unread_count(session, current_user.id)}  # type: ignore[arg-type]


@router.post("/notifications/read-all", summary="Mark every notification read")
@limiter.limit(PUBLIC_LIMIT)
def read_all(
    request: Request,
    response: Response,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    updated = notification_service.mark_all_read(session, current_user.id)  # type: ignore[arg-type]
    return {"status": "read", "updated": updated}


@router.post("/notifications/{notification_id}/read", summary="Mark one notification read")
@limiter.limit(PUBLIC_LIMIT)
def read_notification(
    request: Request,
    response: Response,
    notification_id: int,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    if not notification_service.mark_read(session, notification_id, current_user.id):  # type: ignore[arg-type]
        raise HTTPException(status_code=404, detail="Notification not found")
    return {"status": "read"}
