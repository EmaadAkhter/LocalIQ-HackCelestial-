"""Personalization API: taste profile, interactions and the three graphs.

Backend-only for now (the companion agent and the app consume these). All
endpoints degrade gracefully: with no learned taste yet they fall back to the
deterministic feasibility ranking.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience, User
from app.rate_limit import PUBLIC_LIMIT, RECOMMEND_LIMIT, limiter
from app.schemas import ExperienceResponse
from app.services import graphs, taste
from app.services.auth import get_current_user, get_current_user_optional
from app.services.recommender import resolve_location
from app.services.semantic_search import semantic_search
from app.services.weather import fetch_weather, neutral_weather

logger = logging.getLogger(__name__)
router = APIRouter()


# ---------------------------------------------------------------------------
# Schemas (kept local to this feature to avoid churn in the shared schemas.py)
# ---------------------------------------------------------------------------


class TasteResponse(BaseModel):
    text: str
    vector: dict[str, float]
    likes: list[str]
    avoids: list[str]
    personalization_enabled: bool
    preferred_language: str
    interactions: dict[str, int] = Field(default_factory=dict)


class TasteUpdate(BaseModel):
    text: str | None = Field(default=None, max_length=1000)
    vector: dict[str, float] | None = None
    personalization_enabled: bool | None = None
    preferred_language: str | None = Field(default=None, max_length=8)


class InteractionRequest(BaseModel):
    experience_id: int
    action: str = Field(default="view", max_length=20)
    metadata: dict[str, Any] = Field(default_factory=dict)


class SimilarRequest(BaseModel):
    limit: int = Field(default=6, ge=1, le=20)


class BatchInteractionRequest(BaseModel):
    """Record several interactions at once (e.g. a synced visit history)."""

    interactions: list[InteractionRequest] = Field(default_factory=list, max_length=100)


class MatchRequest(BaseModel):
    limit: int = Field(default=5, ge=1, le=20)


class MatchItem(BaseModel):
    user_id: int | None
    name: str
    taste_tier: str
    score: float
    shared_interests: list[str]
    their_taste: str | None = None


class TasteRecommendRequest(BaseModel):
    location: str | None = None
    origin_lat: float | None = None
    origin_lng: float | None = None
    time_hours: float | None = None
    budget_inr: int | None = None
    start_time: str | None = None
    semantic_query: str | None = None
    limit: int = Field(default=10, ge=1, le=30)


class ScoredExperience(BaseModel):
    experience: ExperienceResponse
    score: float
    parts: dict[str, float]
    distance_km: float
    travel_time_min: int
    why: list[str]


# ---------------------------------------------------------------------------
# Taste profile
# ---------------------------------------------------------------------------


def _taste_response(session: Session, user: User) -> TasteResponse:
    snap = taste.snapshot(user)
    return TasteResponse(
        **snap,
        interactions=taste.interaction_counts(session, user.id or 0),
    )


@router.get("/me/taste", response_model=TasteResponse, summary="My taste profile")
@limiter.limit(PUBLIC_LIMIT)
def get_my_taste(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    return _taste_response(session, current_user)


@router.put("/me/taste", response_model=TasteResponse, summary="Edit my taste profile")
@limiter.limit(PUBLIC_LIMIT)
def update_my_taste(
    request: Request,
    response: Response,
    payload: TasteUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Let the user edit or override what the system learned (PRD 4.6)."""
    if payload.vector is not None:
        taste.set_manual_vector(session, current_user, payload.vector)
    if payload.text is not None:
        current_user.taste_profile_text = payload.text
        session.add(current_user)
        session.commit()
    if payload.personalization_enabled is not None:
        current_user.personalization_enabled = payload.personalization_enabled
        session.add(current_user)
        session.commit()
    if payload.preferred_language is not None:
        current_user.preferred_language = payload.preferred_language
        session.add(current_user)
        session.commit()
    return _taste_response(session, current_user)


@router.post("/me/taste/refresh", response_model=TasteResponse, summary="Regenerate the taste summary")
@limiter.limit(PUBLIC_LIMIT)
async def refresh_my_taste(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    await taste.refresh_taste_text(session, current_user)
    session.add(current_user)
    session.commit()
    session.refresh(current_user)
    return _taste_response(session, current_user)


# ---------------------------------------------------------------------------
# Interactions (implicit signals)
# ---------------------------------------------------------------------------


@router.post("/interactions", response_model=TasteResponse, summary="Record an interaction")
@limiter.limit(PUBLIC_LIMIT)
def record_interaction(
    request: Request,
    response: Response,
    payload: InteractionRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Record a view/save/complete/skip and update the taste vector."""
    experience = session.get(Experience, payload.experience_id)
    if experience is None:
        raise HTTPException(status_code=404, detail="Experience not found")
    taste.record_interaction(
        session, current_user, experience, payload.action, metadata=payload.metadata
    )
    return _taste_response(session, current_user)


@router.post("/interactions/batch", response_model=TasteResponse, summary="Record many interactions")
@limiter.limit(PUBLIC_LIMIT)
def record_interactions_batch(
    request: Request,
    response: Response,
    payload: BatchInteractionRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    for item in payload.interactions:
        experience = session.get(Experience, item.experience_id)
        if experience is None:
            continue
        taste.record_interaction(
            session, current_user, experience, item.action, metadata=item.metadata
        )
    return _taste_response(session, current_user)


# ---------------------------------------------------------------------------
# Graphs
# ---------------------------------------------------------------------------


@router.get(
    "/experiences/{experience_id}/similar",
    response_model=list[ScoredExperience],
    summary="Similar experiences (location -> location)",
)
@limiter.limit(PUBLIC_LIMIT)
def similar_experiences(
    request: Request,
    response: Response,
    experience_id: int,
    limit: int = 6,
    session: Session = Depends(get_session),
):
    if session.get(Experience, experience_id) is None:
        raise HTTPException(status_code=404, detail="Experience not found")
    rows = graphs.similar_experiences(session, experience_id, top_k=max(1, min(limit, 20)))
    return [
        ScoredExperience(
            experience=ExperienceResponse.model_validate(r["experience"]),
            score=r["score"],
            parts=r["parts"],
            distance_km=r["distance_km"],
            travel_time_min=0,
            why=["Similar vibe and nearby"],
        )
        for r in rows
    ]


@router.post(
    "/users/matches",
    response_model=list[MatchItem],
    summary="Taste-compatible users (person -> person)",
)
@limiter.limit(PUBLIC_LIMIT)
def user_matches(
    request: Request,
    response: Response,
    payload: MatchRequest,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Compatible explorers for a meetup. Trust-tier gating is applied by the
    caller: this only reports taste compatibility."""
    rows = graphs.match_users(session, current_user, top_k=payload.limit)
    return [MatchItem(**r) for r in rows]


@router.post(
    "/recommend/taste",
    response_model=list[ScoredExperience],
    summary="Taste-aware, route + weather re-ranked recommendations",
)
@limiter.limit(RECOMMEND_LIMIT)
async def recommend_taste(
    request: Request,
    response: Response,
    payload: TasteRecommendRequest,
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """The reranker layer: semantic pool -> feasibility gate -> taste/route/
    weather re-rank. Works signed-out (no taste vector) as a plain reranker."""
    lat, lng = payload.origin_lat, payload.origin_lng
    if lat is None or lng is None:
        coords = resolve_location(payload.location)
        if coords:
            lat, lng = coords

    try:
        weather = await fetch_weather(lat, lng) if lat is not None and lng is not None else await fetch_weather()
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Weather unavailable for taste recommend: %s", exc)
        weather = neutral_weather(reason="exception")

    candidate_ids: list[int] | None = None
    if payload.semantic_query:
        candidate_ids = await semantic_search(
            session,
            payload.semantic_query,
            top_k=60,
            lat=lat,
            lng=lng,
            radius_km=30.0 if lat is not None else None,
        )

    ranked = graphs.taste_aware_recommend(
        session,
        current_user,
        lat=lat,
        lng=lng,
        time_hours=payload.time_hours,
        budget_inr=payload.budget_inr,
        start_time=payload.start_time,
        weather=weather,
        limit=payload.limit,
        candidate_ids=candidate_ids,
    )
    return [
        ScoredExperience(
            experience=ExperienceResponse.model_validate(r.experience),
            score=r.score,
            parts=r.parts,
            distance_km=r.distance_km,
            travel_time_min=r.travel_time_min,
            why=r.why,
        )
        for r in ranked
    ]
