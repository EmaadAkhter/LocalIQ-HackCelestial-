"""Recommendations API endpoints."""

import hashlib
import json
import logging

from fastapi import APIRouter, Depends, Request, Response
from sqlmodel import Session, func, select

from app.config import get_settings
from app.database import get_session
from app.models import Experience
from app.rate_limit import RECOMMEND_LIMIT, limiter
from app.schemas import ExperienceResponse, RecommendationItem, RecommendationRequest, RecommendationResponse
from app.services import recommender
from app.services.cache import TTLCache
from app.services.weather import fetch_weather

logger = logging.getLogger(__name__)
router = APIRouter()

settings = get_settings()

# Identical constraint sets are common (slider drags, repeated demo runs).
_recommend_cache = TTLCache(
    maxsize=settings.recommend_cache_maxsize,
    ttl_seconds=settings.recommend_cache_ttl_seconds,
)


def clear_recommend_cache() -> None:
    """Drop cached recommendations (used by tests)."""
    _recommend_cache.clear()


def recommend_cache_stats() -> dict[str, int]:
    return _recommend_cache.stats()


def _recommend_cache_key(payload: RecommendationRequest) -> str:
    blob = json.dumps(payload.model_dump(mode="json"), sort_keys=True)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


@router.post("/recommend", response_model=RecommendationResponse, summary="Ranked feasible recommendations")
@limiter.limit(RECOMMEND_LIMIT)
async def get_recommendations(
    request: Request,
    response: Response,
    payload: RecommendationRequest,
    session: Session = Depends(get_session),
):
    """Validate constraints -> feasibility filter -> weather-aware ranking."""
    cache_key = _recommend_cache_key(payload)
    if settings.recommend_cache_enabled:
        cached = _recommend_cache.get(cache_key)
        if cached is not None:
            return cached

    logger.info(
        "Recommend request: location=%s time=%s budget=%s interests=%s",
        payload.location,
        payload.time_hours,
        payload.budget_inr,
        payload.interests,
    )

    # The full pool size is reported to the client ("12 -> 4" reveal), so count
    # it separately from the candidate set we score.
    total_candidates = int(session.exec(select(func.count()).select_from(Experience)).one())

    # Budget is a hard feasibility filter, so apply it in SQL and only load rows
    # that can survive. Everything else (time, hours, distance, accessibility)
    # stays in the ranking engine.
    stmt = select(Experience)
    if payload.budget_inr is not None:
        stmt = stmt.where(Experience.avg_cost <= payload.budget_inr)
    candidates = list(session.exec(stmt).all())

    # Weather is best-effort: failure yields neutral context, never 500.
    try:
        weather = await fetch_weather()
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Weather service raised unexpectedly: %s", exc)
        from app.services.weather import neutral_weather

        weather = neutral_weather(reason="exception")

    result = recommender.recommend(
        candidates,
        location=payload.location,
        time_hours=payload.time_hours,
        budget_inr=payload.budget_inr,
        interests=payload.interests,
        accessibility=payload.accessibility,
        start_time=payload.start_time,
        weather=weather,
        limit=payload.limit,
    )

    items = [
        RecommendationItem(
            experience=ExperienceResponse.model_validate(r.experience),
            score=r.score,
            score_parts=r.score_parts,
            distance_km=r.distance_km,
            travel_time_min=r.travel_time_min,
            total_time_min=r.total_time_min,
            estimated_cost=r.experience.avg_cost,
            why_this_fits=r.why_this_fits,
        )
        for r in result["results"]
    ]
    out = RecommendationResponse(
        total_candidates=total_candidates,
        feasible_count=result["feasible_count"],
        weather_used=result["weather_used"],
        weather_summary=weather.get("description"),
        recommendations=items,
    )

    if settings.recommend_cache_enabled:
        _recommend_cache.set(cache_key, out)
    return out
