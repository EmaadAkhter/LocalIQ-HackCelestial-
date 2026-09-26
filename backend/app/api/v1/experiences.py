"""Experiences API endpoints."""

import logging
import math

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlmodel import Session, func, select

from app.database import get_session
from app.models import Experience, Guide
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.schemas import (
    ExperienceListResponse,
    ExperienceResponse,
    GuideResponse,
    NearbyExperience,
    NearbyListResponse,
)
from app.services.recommender import haversine_km

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/experiences", response_model=ExperienceListResponse, summary="List experiences")
@limiter.limit(PUBLIC_LIMIT)
def list_experiences(
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    category: str | None = Query(default=None, description="Filter by category: food, culture, shopping, art, nightlife, outdoor"),
    q: str | None = Query(default=None, description="Search name/description/tags"),
    min_rating: float | None = Query(default=None, ge=0, le=5),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
):
    """List experiences with optional filtering and pagination."""
    stmt = select(Experience)
    count_stmt = select(func.count()).select_from(Experience)
    filters = []
    if category:
        filters.append(Experience.category == category.lower().strip())
    if min_rating is not None:
        filters.append(Experience.rating >= min_rating)
    if q:
        like = f"%{q.strip()}%"
        filters.append(
            (Experience.name.like(like))  # type: ignore[union-attr]
            | (Experience.description.like(like))  # type: ignore[union-attr]
        )
    for f in filters:
        stmt = stmt.where(f)
        count_stmt = count_stmt.where(f)

    total = session.exec(count_stmt).one()
    items = session.exec(stmt.order_by(Experience.rating.desc()).offset(offset).limit(limit)).all()
    return ExperienceListResponse(
        total=int(total), items=[ExperienceResponse.model_validate(e) for e in items]
    )


@router.get("/experiences/nearby", response_model=NearbyListResponse, summary="Experiences near a point")
@limiter.limit(PUBLIC_LIMIT)
def nearby_experiences(
    request: Request,
    response: Response,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(default=5.0, gt=0, le=50),
    limit: int = Query(default=20, ge=1, le=100),
    session: Session = Depends(get_session),
):
    """Nearest experiences within ``radius_km``.

    A lat/lng bounding box keeps the SQL scan small; the exact haversine
    distance then filters and orders the result.
    """
    lat_delta = radius_km / 111.0
    lng_delta = radius_km / (111.0 * max(0.01, math.cos(math.radians(lat))))

    candidates = session.exec(
        select(Experience).where(
            Experience.lat.between(lat - lat_delta, lat + lat_delta),
            Experience.lng.between(lng - lng_delta, lng + lng_delta),
        )
    ).all()

    scored = [
        (haversine_km(lat, lng, e.lat, e.lng), e)
        for e in candidates
    ]
    scored = [(d, e) for d, e in scored if d <= radius_km]
    scored.sort(key=lambda pair: pair[0])

    items = [
        NearbyExperience(
            experience=ExperienceResponse.model_validate(e), distance_km=round(d, 2)
        )
        for d, e in scored[:limit]
    ]
    return NearbyListResponse(total=len(scored), radius_km=radius_km, items=items)


@router.get("/experiences/{experience_id}", response_model=ExperienceResponse, summary="Get experience by ID")
@limiter.limit(PUBLIC_LIMIT)
def get_experience(
    request: Request,
    response: Response,
    experience_id: int,
    session: Session = Depends(get_session),
):
    """Get a single experience by ID."""
    exp = session.get(Experience, experience_id)
    if not exp:
        raise HTTPException(status_code=404, detail="Experience not found")
    return ExperienceResponse.model_validate(exp)


@router.get(
    "/experiences/{experience_id}/guides",
    response_model=list[GuideResponse],
    summary="Guides for an experience",
)
@limiter.limit(PUBLIC_LIMIT)
def get_experience_guides(
    request: Request,
    response: Response,
    experience_id: int,
    session: Session = Depends(get_session),
):
    """List guides linked to an experience (falls back to area guides)."""
    exp = session.get(Experience, experience_id)
    if not exp:
        raise HTTPException(status_code=404, detail="Experience not found")
    guides = session.exec(select(Guide).where(Guide.experience_id == experience_id)).all()
    if not guides:
        # Fallback: return top-rated guides so the demo never shows an empty page.
        guides = session.exec(select(Guide).order_by(Guide.rating.desc()).limit(4)).all()
    return [GuideResponse.model_validate(g) for g in guides]
