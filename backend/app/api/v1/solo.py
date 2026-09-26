"""Journey 1: Solo Explorer.

Solo-friendly recommendations + an optional (mock) AI companion state.

The existing recommendation engine is reused untouched: this router only layers
solo-friendliness on top of the same feasibility + ranking output, so a solo
search can never disagree with ``POST /api/v1/recommend``.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience
from app.schemas_prd import (
    CompanionStateRequest,
    SoloRecommendation,
    SoloSearchRequest,
    SoloSearchResponse,
)
from app.services import journey_rules as rules
from app.services import recommender

logger = logging.getLogger(__name__)
router = APIRouter()


def _build_solo_results(
    experiences: list[Experience], payload: SoloSearchRequest
) -> list[SoloRecommendation]:
    """Run the standard engine, then annotate with solo-friendliness."""
    ranked = recommender.recommend(
        experiences,
        location=payload.location,
        time_hours=payload.time_hours,
        budget_inr=payload.budget_inr,
        interests=payload.interests,
        accessibility="wheelchair-accessible" if payload.accessibility else None,
        limit=payload.limit * 2,  # widen, then keep the best solo ones
    )

    results: list[SoloRecommendation] = []
    for scored in ranked["results"]:
        place = scored.experience
        solo = rules.solo_friendly_score(place)
        results.append(
            SoloRecommendation(
                experience={
                    "id": place.id,
                    "name": place.name,
                    "category": place.category,
                    "lat": place.lat,
                    "lng": place.lng,
                    "avg_cost": place.avg_cost,
                    "duration_min": place.duration_min,
                    "open_time": place.open_time,
                    "close_time": place.close_time,
                    "rating": place.rating,
                    "description": place.description,
                    "image_url": place.image_url,
                    "tags": list(place.tags or []),
                    "indoor_outdoor": place.indoor_outdoor,
                },
                score=round(scored.score * 0.6 + solo["score"] * 0.4, 2),
                why=scored.why_this_fits,
                solo_friendly=solo["solo_friendly"],
                solo_reasons=solo["reasons"],
            )
        )
    # Solo-friendly first, then the blended score.
    results.sort(key=lambda r: (not r.solo_friendly, -r.score))
    return results[: payload.limit]


@router.post(
    "/solo/explore", response_model=SoloSearchResponse, summary="Solo-friendly recommendations"
)
async def solo_explore(
    payload: SoloSearchRequest, session: Session = Depends(get_session)
):
    """Journey 1: solo + constraints -> solo-friendly recommendations."""
    experiences = list(session.exec(select(Experience)).all())
    results = _build_solo_results(experiences, payload)
    companion = rules.companion_state(payload.companion_enabled, payload.companion_personality)

    logger.info(
        "Solo explore: area=%s time=%s budget=%s solo_friendly=%s",
        payload.location,
        payload.time_hours,
        payload.budget_inr,
        sum(1 for r in results if r.solo_friendly),
    )
    return SoloSearchResponse(
        location=payload.location,
        time_hours=payload.time_hours,
        budget_inr=payload.budget_inr,
        companion=companion,
        total_recommendations=len(results),
        solo_friendly_count=sum(1 for r in results if r.solo_friendly),
        results=results,
    )


@router.post("/solo/companion", summary="Set the AI companion state")
async def set_companion(payload: CompanionStateRequest):
    """Journey 1 optional step: enable/disable the companion (mock state)."""
    return rules.companion_state(payload.enabled, payload.personality)
