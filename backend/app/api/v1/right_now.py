"""Right Now Engine endpoints (PRD 4.8).

* ``POST /recommend/right-now`` — the live feed: taste-ranked candidates blended
  with the moment's weather/crowd/time-of-day score, each with a context panel.
* ``GET  /experiences/{id}/right-now`` — full score breakdown for one venue.
* ``POST /admin/right-now/refresh`` — recompute and persist scores for cards.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlmodel import Session

from app.api.v1.admin import require_admin
from app.database import get_session
from app.models import Experience, User
from app.rate_limit import RECOMMEND_LIMIT, limiter
from app.schemas import ExperienceResponse, RightNowDetail, RightNowItem, RightNowRequest
from app.services import right_now
from app.services.auth import get_current_user_optional
from app.services.recommender import resolve_location
from app.services.weather import fetch_sun_times, fetch_weather, neutral_weather

logger = logging.getLogger(__name__)
router = APIRouter()


async def _resolve_coords(
    lat: float | None, lng: float | None, location: str | None
) -> tuple[float | None, float | None]:
    if lat is None or lng is None:
        coords = resolve_location(location)
        if coords:
            lat, lng = coords
    return lat, lng


async def _conditions(lat: float | None, lng: float | None) -> tuple[dict, dict]:
    """Fetch weather + sun times, never failing the request."""
    try:
        if lat is not None and lng is not None:
            weather = await fetch_weather(lat, lng)
            sun = await fetch_sun_times(lat, lng)
        else:
            weather = await fetch_weather()
            sun = await fetch_sun_times()
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Right Now conditions lookup failed: %s", exc)
        weather = neutral_weather(reason="exception")
        sun = {"available": False}
    return weather, sun


@router.post(
    "/recommend/right-now",
    response_model=list[RightNowItem],
    summary="Live 'Right Now' feed (weather + crowd + time-of-day + taste)",
)
@limiter.limit(RECOMMEND_LIMIT)
async def recommend_right_now(
    request: Request,
    response: Response,
    payload: RightNowRequest,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    lat, lng = await _resolve_coords(payload.origin_lat, payload.origin_lng, payload.location)
    weather, sun = await _conditions(lat, lng)

    items = right_now.right_now_feed(
        session,
        current_user,
        lat=lat,
        lng=lng,
        time_hours=payload.time_hours,
        budget_inr=payload.budget_inr,
        start_time=payload.start_time,
        weather=weather,
        sun=sun,
        limit=payload.limit,
    )
    return [
        RightNowItem(
            experience=ExperienceResponse.model_validate(item["experience"]),
            right_now_score=item["right_now_score"],
            right_now_label=item["right_now_label"],
            context=item["context"],
            components=item["components"],
            rerank_score=item["rerank_score"],
            final_score=item["final_score"],
            distance_km=item["distance_km"],
            travel_time_min=item["travel_time_min"],
            why=item["why"],
        )
        for item in items
    ]


@router.get(
    "/experiences/{experience_id}/right-now",
    response_model=RightNowDetail,
    summary="Right Now score breakdown for one experience",
)
@limiter.limit(RECOMMEND_LIMIT)
async def experience_right_now(
    request: Request,
    response: Response,
    experience_id: int,
    session: Session = Depends(get_session),
):
    experience = session.get(Experience, experience_id)
    if experience is None:
        raise HTTPException(status_code=404, detail="Experience not found")
    weather, sun = await _conditions(experience.lat, experience.lng)
    result = right_now.score_for(experience, weather=weather, sun=sun)
    return RightNowDetail(
        experience_id=experience.id or 0,
        name=experience.name,
        right_now_score=result["score"],
        right_now_label=result["label"],
        components=result["components"],
        context=result["context"],
        computed_at=result.get("computed_at"),
    )


@router.post(
    "/admin/right-now/refresh",
    summary="Recompute stored Right Now scores",
    dependencies=[Depends(require_admin)],
)
@limiter.limit(RECOMMEND_LIMIT)
async def refresh_right_now(
    request: Request,
    response: Response,
    lat: float | None = None,
    lng: float | None = None,
    limit: int | None = None,
    session: Session = Depends(get_session),
):
    count = await right_now.refresh_scores(session, lat=lat, lng=lng, limit=limit)
    return {"refreshed": count}
