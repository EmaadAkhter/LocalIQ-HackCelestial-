"""Guides API endpoints (local DB persistence, no payments)."""

import logging
import secrets

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, Guide, GuideRequest, User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import GuideRequestPayload, GuideRequestResponse, GuideResponse
from app.services.auth import get_current_user, get_current_user_optional

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/guides", response_model=list[GuideResponse], summary="List guides")
@limiter.limit(PUBLIC_LIMIT)
def list_guides(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
):
    guides = session.exec(select(Guide).order_by(Guide.rating.desc())).all()
    return [GuideResponse.model_validate(g) for g in guides]


@router.get("/guides/me/requests", response_model=list[GuideRequestResponse], summary="My guide requests")
@limiter.limit(PUBLIC_LIMIT)
def my_requests(
    request: Request,
    response: Response,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """All guide requests made by the authenticated user, newest first."""
    rows = session.exec(
        select(GuideRequest)
        .where(GuideRequest.user_id == current_user.id)
        .order_by(GuideRequest.id.desc())
    ).all()
    return [
        GuideRequestResponse(
            status="confirmed_mock",
            guide_id=r.guide_id,
            experience_id=r.experience_id,
            message=f"Request for {r.hours}h with {r.group_size} guests on {r.date or 'unspecified date'}.",
            booking_ref=r.booking_ref,
            booking_id=r.id,
            created_at=r.created_at,
        )
        for r in rows
    ]


@router.post(
    "/guides/{guide_id}/request",
    response_model=GuideRequestResponse,
    summary="Request a guide (persisted locally)",
)
@limiter.limit(PUBLIC_LIMIT)
def request_guide(
    request: Request,
    response: Response,
    guide_id: int,
    payload: GuideRequestPayload,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """Create a guide request.

    Auth is optional so the demo flow still works, but when a token is supplied
    the request is linked to that user and retrievable via
    ``GET /api/v1/guides/me/requests``.
    """
    guide = session.get(Guide, guide_id)
    if not guide:
        raise HTTPException(status_code=404, detail="Guide not found")
    if guide.experience_id is not None and session.get(Experience, guide.experience_id) is None:
        raise HTTPException(status_code=400, detail="Guide is linked to a missing experience")

    ref = f"LQ-{secrets.token_hex(3).upper()}"
    requester = (payload.name or (current_user.name if current_user else "Guest")).strip()

    row = GuideRequest(
        user_id=current_user.id if current_user else None,
        guide_id=guide.id or guide_id,  # type: ignore[arg-type]
        experience_id=guide.experience_id,
        requester_name=requester,
        date=payload.date,
        hours=payload.hours,
        group_size=payload.group_size,
        note=payload.note,
        booking_ref=ref,
    )
    session.add(row)
    session.commit()
    session.refresh(row)

    logger.info("Guide request stored: ref=%s guide=%s user=%s", ref, guide_id, row.user_id)
    return GuideRequestResponse(
        status="confirmed_mock",
        guide_id=guide_id,
        experience_id=guide.experience_id,
        message=(
            f"Mock booking confirmed with {guide.name} ({guide.specialty}) "
            f"for {payload.hours}h, {payload.group_size} guests. No payment taken."
        ),
        booking_ref=ref,
        booking_id=row.id,
        created_at=row.created_at,
    )
