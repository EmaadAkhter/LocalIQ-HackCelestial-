"""Recommendations API endpoints."""

import logging

from fastapi import APIRouter, Depends, Request, Response
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience
from app.rate_limit import RECOMMEND_LIMIT, limiter
from app.schemas import ExperienceResponse, RecommendationItem, RecommendationRequest, RecommendationResponse
from app.services import recommender
from app.services.weather import fetch_weather

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/recommend", response_model=RecommendationResponse, summary="Ranked feasible recommendations")
@limiter.limit(RECOMMEND_LIMIT)
async def get_recommendations(
    request: Request,
    response: Response,
    payload: RecommendationRequest,
    session: Session = Depends(get_session),
):
    """Validate constraints -> feasibility filter -> weather-aware ranking."""
    logger.info(
        "Recommend request: location=%s time=%s budget=%s interests=%s",
        payload.location,
        payload.time_hours,
        payload.budget_inr,
        payload.interests,
    )
    experiences = session.exec(select(Experience)).all()

    # Weather is best-effort: failure yields neutral context, never 500.
    try:
        weather = await fetch_weather()
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Weather service raised unexpectedly: %s", exc)
        from app.services.weather import neutral_weather

        weather = neutral_weather(reason="exception")

    result = recommender.recommend(
        list(experiences),
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
    return RecommendationResponse(
        total_candidates=result["total_candidates"],
        feasible_count=result["feasible_count"],
        weather_used=result["weather_used"],
        weather_summary=weather.get("description"),
        recommendations=items,
    )
