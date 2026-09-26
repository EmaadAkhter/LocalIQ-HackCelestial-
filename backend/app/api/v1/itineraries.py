"""Itinerary CRUD + the A-to-Z planner, export/import and sharing.

Endpoints fall into four groups:

* CRUD — create/get/list/update/delete a user's saved plans.
* Planner — ``generate`` builds a full day from constraints; ``optimize`` cuts
  travel time on an existing plan.
* Portability — ``export`` (JSON / ICS / text), ``import`` (JSON rows or loose
  text), and a read-only ``shared/{token}`` link.
* Taste — every stop added to a plan is an ``add_to_itinerary`` signal, so the
  things people actually plan to do shape their taste vector.
"""

from __future__ import annotations

import logging
import secrets
from datetime import date as date_type

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi import status as http_status
from fastapi.responses import JSONResponse
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, Itinerary, ItineraryStop, User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import (
    ExperienceResponse,
    ItineraryCreate,
    ItineraryGenerateRequest,
    ItineraryImportRequest,
    ItineraryImportResponse,
    ItineraryResponse,
    ItineraryShareResponse,
    ItineraryStopInput,
    ItineraryStopResponse,
    ItineraryUpdate,
)
from app.services import itinerary_planner, taste
from app.services.auth import get_current_user
from app.services.recommender import (
    estimate_travel_time_min,
    haversine_km,
    parse_hhmm,
    resolve_location,
)
from app.services.semantic_search import semantic_search
from app.services.weather import fetch_weather, neutral_weather

logger = logging.getLogger(__name__)
router = APIRouter()

DAY_MINUTES = 24 * 60


def _slug(text: str) -> str:
    return "".join(c if c.isalnum() else "-" for c in (text or "itinerary").lower()).strip("-") or "itinerary"


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


def _ordered_experiences(session: Session, itinerary: Itinerary) -> list[Experience]:
    """Experiences in stop order, skipping any dangling references."""
    stop_rows = sorted(itinerary.stops, key=lambda s: s.sequence)
    ids = [s.experience_id for s in stop_rows]
    if not ids:
        return []
    rows = session.exec(select(Experience).where(Experience.id.in_(ids))).all()
    by_id = {e.id: e for e in rows}
    return [by_id[i] for i in ids if i in by_id]


def _record_plan_taste(session: Session, user: User, experiences: list[Experience]) -> None:
    """Adding places to a plan means the user intends to go — learn from it."""
    if experiences:
        taste.record_signals(
            session, user, [(exp, "add_to_itinerary") for exp in experiences]
        )


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------


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
    _record_plan_taste(session, current_user, experiences)
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


# ---------------------------------------------------------------------------
# Planner — declared before /itineraries/{id} so "generate"/"import" win.
# ---------------------------------------------------------------------------


@router.post(
    "/itineraries/generate",
    response_model=ItineraryResponse,
    status_code=http_status.HTTP_201_CREATED,
    summary="Auto-plan a full day (A to Z)",
)
@limiter.limit(PUBLIC_LIMIT)
async def generate_itinerary(
    request: Request,
    response: Response,
    payload: ItineraryGenerateRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Build and save a time-aware day plan from constraints + taste."""
    origin = resolve_location(payload.start_location) if payload.start_location else None
    try:
        weather = (
            await fetch_weather(origin[0], origin[1])
            if origin
            else await fetch_weather()
        )
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Planner weather lookup failed: %s", exc)
        weather = neutral_weather(reason="exception")

    candidate_ids: list[int] | None = None
    if payload.semantic_query:
        candidate_ids = await semantic_search(
            session,
            payload.semantic_query,
            top_k=60,
            lat=origin[0] if origin else None,
            lng=origin[1] if origin else None,
            radius_km=30.0 if origin else None,
        )

    plan = itinerary_planner.plan_day(
        session,
        current_user,
        start_location=payload.start_location,
        start_time=payload.start_time,
        duration_hours=payload.duration_hours,
        budget_inr=payload.budget_inr,
        travel_mode=payload.travel_mode,
        interests=payload.interests,
        weather=weather,
        include_food=payload.include_food,
        max_stops=payload.max_stops,
        semantic_query=payload.semantic_query,
        candidate_ids=candidate_ids,
    )

    itinerary = Itinerary(
        user_id=current_user.id,
        name=payload.name,
        total_duration_min=plan.total_duration_min,
        total_cost=plan.total_cost,
    )
    itinerary_planner.apply_plan_to_itinerary(itinerary, plan.stops)
    session.add(itinerary)
    session.commit()
    session.refresh(itinerary)
    _record_plan_taste(session, current_user, [s.experience for s in plan.stops])
    logger.info(
        "Generated itinerary %s for user %s (%d stops, %d notes)",
        itinerary.id,
        current_user.id,
        len(plan.stops),
        len(plan.notes),
    )
    return _serialize(session, itinerary)


@router.post(
    "/itineraries/import",
    response_model=ItineraryImportResponse,
    status_code=http_status.HTTP_201_CREATED,
    summary="Import a plan from JSON rows or loose text",
)
@limiter.limit(PUBLIC_LIMIT)
def import_itinerary(
    request: Request,
    response: Response,
    payload: ItineraryImportRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Create a plan from a JSON export, a list of place names, or plain text."""
    rows: list[dict] = []
    if payload.format == "text" or payload.text:
        rows = itinerary_planner.parse_itinerary_text(payload.text or "")
    if payload.stops:
        rows = [
            {
                "experience_id": s.experience_id,
                "name": s.name,
                "start_time": s.start_time,
            }
            for s in payload.stops
        ] + rows

    resolved, unresolved = itinerary_planner.resolve_import_stops(session, rows)
    if not resolved:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "No stops could be matched to known experiences.",
                "unresolved": unresolved,
            },
        )

    experiences = [exp for exp, _ in resolved]
    itinerary = Itinerary(user_id=current_user.id, name=payload.name)
    if payload.optimize:
        # Re-sequence by nearest-neighbour and recompute times from the first
        # explicit time (or 10:00), keeping the user's first stop as the anchor.
        anchor_time = next((start for _, start in resolved if start), "10:00")
        plan = itinerary_planner.optimize_order(
            experiences, origin=None, start_time=anchor_time
        )
        itinerary_planner.apply_plan_to_itinerary(itinerary, plan)
    else:
        stops_input: list[ItineraryStopInput] = [
            ItineraryStopInput(experience_id=exp.id, start_time=start)  # type: ignore[arg-type]
            for exp, start in resolved
        ]
        stops, total_duration, total_cost = _build_stops(stops_input, experiences)
        itinerary.stops = stops
        itinerary.total_duration_min = total_duration
        itinerary.total_cost = total_cost

    session.add(itinerary)
    session.commit()
    session.refresh(itinerary)
    _record_plan_taste(session, current_user, experiences)
    return ItineraryImportResponse(
        itinerary=_serialize(session, itinerary), unresolved=unresolved
    )


@router.get(
    "/itineraries/shared/{token}",
    response_model=ItineraryResponse,
    summary="View a shared itinerary (public)",
)
@limiter.limit(PUBLIC_LIMIT)
def get_shared_itinerary(
    request: Request,
    response: Response,
    token: str,
    session: Session = Depends(get_session),
):
    itinerary = session.exec(
        select(Itinerary).where(Itinerary.share_token == token)
    ).first()
    if itinerary is None:
        raise HTTPException(status_code=404, detail="Shared itinerary not found")
    return _serialize(session, itinerary)


# ---------------------------------------------------------------------------
# Single-itinerary routes
# ---------------------------------------------------------------------------


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
        before_ids = [s.experience_id for s in itinerary.stops]
        experiences = _load_experiences(session, payload.stops)
        stops, total_duration, total_cost = _build_stops(payload.stops, experiences)
        itinerary.stops.clear()
        itinerary.stops.extend(stops)
        itinerary.total_duration_min = total_duration
        itinerary.total_cost = total_cost

        # Taste: new stops are a positive signal; removed ones a negative one.
        after_ids = [s.experience_id for s in stops]
        added = [e for e in experiences if e.id not in before_ids]
        removed_ids = [i for i in before_ids if i not in after_ids]
        if added:
            _record_plan_taste(session, current_user, added)
        if removed_ids:
            removed = session.exec(
                select(Experience).where(Experience.id.in_(removed_ids))
            ).all()
            taste.record_signals(
                session, current_user, [(e, "remove_from_itinerary") for e in removed]
            )
    session.add(itinerary)
    session.commit()
    session.refresh(itinerary)
    return _serialize(session, itinerary)


@router.post(
    "/itineraries/{itinerary_id}/optimize",
    response_model=ItineraryResponse,
    summary="Re-order stops to cut travel time",
)
@limiter.limit(PUBLIC_LIMIT)
def optimize_itinerary(
    request: Request,
    response: Response,
    itinerary_id: int,
    start_location: str | None = None,
    start_time: str = "10:00",
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    itinerary = _get_owned(session, itinerary_id, current_user)
    experiences = _ordered_experiences(session, itinerary)
    if not experiences:
        raise HTTPException(status_code=422, detail="Itinerary has no resolvable stops")
    origin = resolve_location(start_location) if start_location else None
    plan = itinerary_planner.optimize_order(
        experiences, origin=origin, start_time=start_time
    )
    itinerary_planner.apply_plan_to_itinerary(itinerary, plan)
    session.add(itinerary)
    session.commit()
    session.refresh(itinerary)
    return _serialize(session, itinerary)


@router.get(
    "/itineraries/{itinerary_id}/export",
    summary="Export an itinerary (json | ics | text)",
)
@limiter.limit(PUBLIC_LIMIT)
def export_itinerary(
    request: Request,
    response: Response,
    itinerary_id: int,
    format: str = "json",
    date: str | None = None,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    itinerary = _get_owned(session, itinerary_id, current_user)
    payload = _serialize(session, itinerary)
    on_date: date_type | None = None
    if date:
        try:
            on_date = date_type.fromisoformat(date)
        except ValueError:
            raise HTTPException(status_code=422, detail="date must be YYYY-MM-DD")

    slug = _slug(itinerary.name)
    if format == "ics":
        stops = [(s.experience, s.start_time, s.end_time) for s in payload.stops]  # type: ignore[arg-type]
        body = itinerary_planner.itinerary_to_ics(itinerary, stops, on_date=on_date)
        return Response(
            content=body,
            media_type="text/calendar",
            headers={"Content-Disposition": f'attachment; filename="{slug}.ics"'},
        )
    if format == "text":
        return Response(
            content=_export_text(payload),
            media_type="text/plain; charset=utf-8",
            headers={"Content-Disposition": f'attachment; filename="{slug}.txt"'},
        )
    return JSONResponse(content=payload.model_dump(mode="json"))


@router.post(
    "/itineraries/{itinerary_id}/share",
    response_model=ItineraryShareResponse,
    summary="Create (or reuse) a public share link",
)
@limiter.limit(PUBLIC_LIMIT)
def share_itinerary(
    request: Request,
    response: Response,
    itinerary_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    itinerary = _get_owned(session, itinerary_id, current_user)
    if not itinerary.share_token:
        itinerary.share_token = secrets.token_urlsafe(16)
        session.add(itinerary)
        session.commit()
        session.refresh(itinerary)
    base = str(request.base_url).rstrip("/")
    return ItineraryShareResponse(
        share_token=itinerary.share_token,
        url=f"{base}/api/v1/itineraries/shared/{itinerary.share_token}",
        itinerary=_serialize(session, itinerary),
    )


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


def _export_text(payload: ItineraryResponse) -> str:
    """Human-readable plan (printable / shareable as plain text)."""
    hours, minutes = divmod(payload.total_duration_min, 60)
    header = (
        f"{payload.name}\n"
        f"{len(payload.stops)} stops · {hours}h {minutes:02d}m · ₹{payload.total_cost}\n"
        + "=" * 48
    )
    lines = [header]
    for stop in payload.stops:
        exp = stop.experience
        travel = f"  (+{stop.travel_time_min} min travel)" if stop.travel_time_min else ""
        lines.append(
            f"{stop.start_time}–{stop.end_time}  {exp.name} [{exp.category}]{travel}\n"
            f"      ₹{exp.avg_cost} · {exp.duration_min} min · rating {exp.rating:.1f}\n"
            f"      https://www.google.com/maps/search/?api=1&query={exp.lat},{exp.lng}"
        )
    return "\n".join(lines) + "\n"
