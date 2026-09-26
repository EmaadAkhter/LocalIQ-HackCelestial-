"""Itinerary CRUD — user-owned saved plans."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi import status as http_status
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, Itinerary, ItineraryStop, User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import (
    ExperienceResponse,
    ItineraryCreate,
    ItineraryResponse,
    ItineraryStopInput,
    ItineraryStopResponse,
    ItineraryUpdate,
)
from app.services.auth import get_current_user
from app.services.recommender import estimate_travel_time_min, haversine_km, parse_hhmm

logger = logging.getLogger(__name__)
router = APIRouter()

DAY_MINUTES = 24 * 60


def _load_experiences(
    session: Session, stops: list[ItineraryStopInput]
) -> list[Experience]:
    """Resolve stop experiences in order, failing loudly on unknown ids."""
    ids = [s.experience_id for s in stops]
    rows = session.exec(select(Experience).where(Experience.id.in_(ids))).all()
    by_id = {e.id: e for e in rows}
    missing = sorted({i for i in ids if i not in by_id})
    if missing:
        raise HTTPException(status_code=400, detail=f"Unknown experience_id(s): {missing}")
    return [by_id[s.experience_id] for s in stops]


def _build_stops(
    stops_input: list[ItineraryStopInput], experiences: list[Experience]
) -> tuple[list[ItineraryStop], int, int]:
    """Create stops with travel time + chained opening times; return totals."""
    stops: list[ItineraryStop] = []
    total_duration = 0
    total_cost = 0
    previous: Experience | None = None
    previous_end: int | None = None

    for sequence, (item, experience) in enumerate(zip(stops_input, experiences)):
        travel = 0
        if previous is not None:
            travel = estimate_travel_time_min(
                haversine_km(previous.lat, previous.lng, experience.lat, experience.lng)
            )
        total_duration += experience.duration_min + travel
        total_cost += experience.avg_cost

        start_min = parse_hhmm(item.start_time) if item.start_time else None
        if start_min is None and previous_end is not None:
            start_min = previous_end + travel

        start_time = end_time = ""
        if start_min is not None:
            start_min %= DAY_MINUTES
            end_min = start_min + experience.duration_min
            start_time = f"{start_min // 60:02d}:{start_min % 60:02d}"
            end_time = f"{(end_min // 60) % 24:02d}:{end_min % 60:02d}"
            previous_end = end_min
        else:
            previous_end = None

        stops.append(
            ItineraryStop(
                experience_id=experience.id,  # type: ignore[arg-type]
                sequence=sequence,
                start_time=start_time,
                end_time=end_time,
                travel_time_min=travel,
            )
        )
        previous = experience

    return stops, total_duration, total_cost


def _serialize(session: Session, itinerary: Itinerary) -> ItineraryResponse:
    stop_rows = sorted(itinerary.stops, key=lambda s: s.sequence)
    if stop_rows:
        ids = [s.experience_id for s in stop_rows]
        rows = session.exec(select(Experience).where(Experience.id.in_(ids))).all()
        by_id = {e.id: e for e in rows}
    else:
        by_id = {}

    stops = [
        ItineraryStopResponse(
            id=stop.id,  # type: ignore[arg-type]
            experience_id=stop.experience_id,
            experience=ExperienceResponse.model_validate(by_id[stop.experience_id]),
            sequence=stop.sequence,
            start_time=stop.start_time,
            end_time=stop.end_time,
            travel_time_min=stop.travel_time_min,
        )
        for stop in stop_rows
        if stop.experience_id in by_id
    ]
    return ItineraryResponse(
        id=itinerary.id,  # type: ignore[arg-type]
        name=itinerary.name,
        total_duration_min=itinerary.total_duration_min,
        total_cost=itinerary.total_cost,
        created_at=itinerary.created_at,
        stops=stops,
    )


def _get_owned(session: Session, itinerary_id: int, user: User) -> Itinerary:
    itinerary = session.get(Itinerary, itinerary_id)
    if itinerary is None or itinerary.user_id != user.id:
        raise HTTPException(status_code=404, detail="Itinerary not found")
    return itinerary


@router.post(
    "/itineraries",
    response_model=ItineraryResponse,
    status_code=http_status.HTTP_201_CREATED,
    summary="Create an itinerary",
)
@limiter.limit(PUBLIC_LIMIT)
def create_itinerary(
    request: Request,
    response: Response,
    payload: ItineraryCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    experiences = _load_experiences(session, payload.stops)
    stops, total_duration, total_cost = _build_stops(payload.stops, experiences)

    itinerary = Itinerary(
        user_id=current_user.id,
        name=payload.name,
        total_duration_min=total_duration,
        total_cost=total_cost,
    )
    itinerary.stops = stops
    session.add(itinerary)
    session.commit()
    session.refresh(itinerary)
    logger.info("Itinerary %s created for user %s (%d stops)", itinerary.id, current_user.id, len(stops))
    return _serialize(session, itinerary)


@router.get("/itineraries", response_model=list[ItineraryResponse], summary="List my itineraries")
@limiter.limit(PUBLIC_LIMIT)
def list_itineraries(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    rows = session.exec(
        select(Itinerary)
        .where(Itinerary.user_id == current_user.id)
        .order_by(Itinerary.created_at.desc())
    ).all()
    return [_serialize(session, itinerary) for itinerary in rows]


@router.get("/itineraries/{itinerary_id}", response_model=ItineraryResponse, summary="Get an itinerary")
@limiter.limit(PUBLIC_LIMIT)
def get_itinerary(
    request: Request,
    response: Response,
    itinerary_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    return _serialize(session, _get_owned(session, itinerary_id, current_user))


@router.put("/itineraries/{itinerary_id}", response_model=ItineraryResponse, summary="Update an itinerary")
@limiter.limit(PUBLIC_LIMIT)
def update_itinerary(
    request: Request,
    response: Response,
    itinerary_id: int,
    payload: ItineraryUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    itinerary = _get_owned(session, itinerary_id, current_user)
    if payload.name is not None:
        itinerary.name = payload.name
    if payload.stops is not None:
        experiences = _load_experiences(session, payload.stops)
        stops, total_duration, total_cost = _build_stops(payload.stops, experiences)
        itinerary.stops.clear()
        itinerary.stops.extend(stops)
        itinerary.total_duration_min = total_duration
        itinerary.total_cost = total_cost
    session.add(itinerary)
    session.commit()
    session.refresh(itinerary)
    return _serialize(session, itinerary)


@router.delete(
    "/itineraries/{itinerary_id}",
    status_code=http_status.HTTP_204_NO_CONTENT,
    summary="Delete an itinerary",
)
@limiter.limit(PUBLIC_LIMIT)
def delete_itinerary(
    request: Request,
    response: Response,
    itinerary_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    itinerary = _get_owned(session, itinerary_id, current_user)
    session.delete(itinerary)
    session.commit()
    return Response(status_code=http_status.HTTP_204_NO_CONTENT)
