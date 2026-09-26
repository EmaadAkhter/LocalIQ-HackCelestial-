"""AI Experience Director endpoints (PRD 4.10).

A live session that spans the outing:

* ``POST /director/sessions`` — start for an experience or an itinerary.
* ``GET  /director/sessions/{id}`` — current session state.
* ``POST /director/sessions/{id}/check-in`` — next location-aware tip.
* ``POST /director/sessions/{id}/adapt`` — react to a context change.
* ``POST /director/sessions/{id}/end`` — summarise + log to the wallet.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi import status as http_status
from sqlmodel import Session

from app.database import get_session
from app.models import ExperienceSession, User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import (
    AITipView,
    DirectorAdaptResponse,
    DirectorCheckInRequest,
    DirectorEndRequest,
    DirectorEndResponse,
    DirectorSessionView,
    DirectorStartRequest,
    DirectorTipResponse,
    ExperienceResponse,
)
from app.services import experience_director as director
from app.services.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()


def _view(session: Session, live: ExperienceSession) -> DirectorSessionView:
    stops = [
        {
            "experience_id": e.id,
            "name": e.name,
            "category": e.category,
            "lat": e.lat,
            "lng": e.lng,
            "image_key": e.image_key,
        }
        for e in director.session_experiences(session, live)
    ]
    return DirectorSessionView(
        id=live.id or 0,
        status=live.status,
        language=live.language,
        experience_id=live.experience_id,
        itinerary_id=live.itinerary_id,
        start_time=live.start_time,
        end_time=live.end_time,
        stops=stops,
        summary=dict(live.summary_json or {}),
        shown_tip_ids=list((live.live_context_json or {}).get("shown_tip_ids") or []),
    )


def _owned(session: Session, session_id: int, user: User) -> ExperienceSession:
    try:
        return director.get_owned(session, session_id, user)
    except LookupError:
        raise HTTPException(status_code=404, detail="Session not found")


@router.post(
    "/director/sessions",
    response_model=DirectorSessionView,
    status_code=http_status.HTTP_201_CREATED,
    summary="Start a live companion session",
)
@limiter.limit(PUBLIC_LIMIT)
async def start_session(
    request: Request,
    response: Response,
    payload: DirectorStartRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    try:
        live = await director.start_session(
            session,
            current_user,
            experience_id=payload.experience_id,
            itinerary_id=payload.itinerary_id,
            language=payload.language,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    return _view(session, live)


@router.get(
    "/director/sessions/{session_id}",
    response_model=DirectorSessionView,
    summary="Current state of a companion session",
)
@limiter.limit(PUBLIC_LIMIT)
def get_session_state(
    request: Request,
    response: Response,
    session_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    return _view(session, _owned(session, session_id, current_user))


@router.post(
    "/director/sessions/{session_id}/check-in",
    response_model=DirectorTipResponse,
    summary="Next location-aware tip",
)
@limiter.limit(PUBLIC_LIMIT)
def check_in(
    request: Request,
    response: Response,
    session_id: int,
    payload: DirectorCheckInRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    live = _owned(session, session_id, current_user)
    result = director.next_tip(session, live, lat=payload.lat, lng=payload.lng)
    tip = result.get("tip")
    return DirectorTipResponse(
        session_id=live.id or 0,
        tip=AITipView(**tip) if tip else None,
        remaining=result.get("remaining", 0),
        message=result.get("message", ""),
    )


@router.post(
    "/director/sessions/{session_id}/adapt",
    response_model=DirectorAdaptResponse,
    summary="Adapt the plan to a context change (rain/crowd)",
)
@limiter.limit(PUBLIC_LIMIT)
async def adapt_session(
    request: Request,
    response: Response,
    session_id: int,
    payload: DirectorCheckInRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    live = _owned(session, session_id, current_user)
    result = await director.adapt(session, live, lat=payload.lat, lng=payload.lng)
    suggestion = result.get("suggestion")
    return DirectorAdaptResponse(
        session_id=live.id or 0,
        adaptation_needed=bool(result.get("adaptation_needed")),
        message=result.get("message", ""),
        suggestion=ExperienceResponse.model_validate(suggestion) if suggestion else None,
        travel_time_min=int(result.get("travel_time_min") or 0),
        why=list(result.get("why") or []),
    )


@router.post(
    "/director/sessions/{session_id}/end",
    response_model=DirectorEndResponse,
    summary="End the outing: summarise and log to the wallet",
)
@limiter.limit(PUBLIC_LIMIT)
def end_session(
    request: Request,
    response: Response,
    session_id: int,
    payload: DirectorEndRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    live = _owned(session, session_id, current_user)
    result = director.end_session(
        session, live, rating=payload.rating, notes=payload.notes
    )
    return DirectorEndResponse(
        session_id=live.id or 0,
        status=live.status,
        summary=result["summary"],
        new_badges=result["new_badges"],
    )
