"""Place discovery / search backed by the Google Places API (New).

Contract for clients (Flutter, Next.js):

* ``GET /api/v1/places/search`` returns a **LocalIQ-shaped** payload. Google's
  response is normalized in :mod:`app.services.google_places`; the client never
  sees a Google field name.
* When Google is unconfigured or fails, the endpoint transparently falls back to
  searching the local SQLite experience dataset, and says so via ``source``.

No Google API key is ever returned to the client. Photo URLs point at the
LocalIQ proxy in :mod:`app.api.v1.places`.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience
from app.schemas import PlaceSearchResponse, PlaceSearchResult
from app.services import google_places, google_routes
from app.services.recommender import estimate_travel_time_min, haversine_km

logger = logging.getLogger(__name__)
router = APIRouter()


def _local_results(
    session: Session,
    query: str,
    lat: float | None,
    lng: float | None,
    limit: int,
) -> list[PlaceSearchResult]:
    """SQLite fallback: curated experiences filtered by text/category."""
    like = f"%{query.strip()}%"
    stmt = select(Experience)
    if query.strip():
        stmt = stmt.where(
            (Experience.name.like(like))  # type: ignore[union-attr]
            | (Experience.category.like(like))  # type: ignore[union-attr]
            | (Experience.description.like(like))  # type: ignore[union-attr]
        )
    rows = list(session.exec(stmt.limit(limit * 3)).all())

    # Relevance: exact/name matches first, then category, then description.
    needle = query.strip().lower()
    rows.sort(
        key=lambda e: (
            0 if needle and needle in e.name.lower() else (1 if needle in e.category.lower() else 2),
            -e.rating,
        )
    )

    results: list[PlaceSearchResult] = []
    for exp in rows[:limit]:
        distance_km = None
        travel_minutes = None
        if lat is not None and lng is not None:
            distance_km = round(haversine_km(lat, lng, exp.lat, exp.lng), 2)
            travel_minutes = estimate_travel_time_min(distance_km)
        results.append(
            PlaceSearchResult(
                id=str(exp.id),
                name=exp.name,
                category=exp.category,
                address="",
                description=exp.description,
                lat=exp.lat,
                lng=exp.lng,
                rating=exp.rating,
                review_count=0,
                avg_cost=exp.avg_cost,
                image_url=exp.image_url or None,
                open_time=exp.open_time,
                close_time=exp.close_time,
                open_now=None,
                distance_km=distance_km,
                travel_minutes=travel_minutes,
                source="sqlite",
            )
        )
    return results


@router.get(
    "/places/search",
    response_model=PlaceSearchResponse,
    summary="Search places (Google Places API, SQLite fallback)",
)
async def search_places(
    q: str = Query(..., min_length=1, max_length=200, description="Free-text query"),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    radius_m: int = Query(default=8000, ge=100, le=50000),
    limit: int = Query(default=10, ge=1, le=20),
    session: Session = Depends(get_session),
):
    """Discover places by text.

    Pass ``lat``/``lng`` to bias results toward the user. With no server-side
    Places key configured (or on any Google error) the curated SQLite dataset is
    searched instead and ``source`` reports ``sqlite``.
    """
    return await _search(q, lat, lng, radius_m, limit, session)


async def _search(q: str, lat, lng, radius_m, limit, session) -> PlaceSearchResponse:
    google_results = await google_places.search_places(
        q, lat=lat, lng=lng, radius_m=radius_m, page_size=limit
    )
    if google_results:
        items = [
            PlaceSearchResult(
                id=r.google_place_id,
                name=r.name,
                category=r.category,
                address=r.address,
                description=r.description,
                lat=r.lat,
                lng=r.lng,
                rating=r.rating,
                review_count=r.review_count,
                avg_cost=r.avg_cost,
                image_url=r.image_url,
                open_time=r.open_time,
                close_time=r.close_time,
                open_now=r.open_now,
                distance_km=(
                    round(haversine_km(lat, lng, r.lat, r.lng), 2)
                    if lat is not None and lng is not None
                    else None
                ),
                travel_minutes=None,
                source="google_places",
            )
            for r in google_results
        ]
        return PlaceSearchResponse(
            query=q,
            source="google_places",
            count=len(items),
            items=items,
            fallback=False,
        )

    logger.info("Google Places unavailable; falling back to SQLite for %r", q)
    items_local = _local_results(session, q, lat, lng, limit)
    return PlaceSearchResponse(
        query=q,
        source="sqlite",
        count=len(items_local),
        items=items_local,
        fallback=True,
    )


@router.get("/places/nearby", response_model=PlaceSearchResponse, summary="Nearby places")
async def nearby_places(
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_m: int = Query(default=3000, ge=100, le=50000),
    limit: int = Query(default=10, ge=1, le=20),
    session: Session = Depends(get_session),
):
    """Nearby discovery via Google; falls back to the nearest SQLite places."""
    google_results = await google_places.search_nearby(
        lat, lng, radius_m=radius_m, page_size=limit
    )
    if google_results:
        items = [
            PlaceSearchResult(
                id=r.google_place_id,
                name=r.name,
                category=r.category,
                address=r.address,
                description=r.description,
                lat=r.lat,
                lng=r.lng,
                rating=r.rating,
                review_count=r.review_count,
                avg_cost=r.avg_cost,
                image_url=r.image_url,
                open_time=r.open_time,
                close_time=r.close_time,
                open_now=r.open_now,
                distance_km=round(haversine_km(lat, lng, r.lat, r.lng), 2),
                travel_minutes=None,
                source="google_places",
            )
            for r in google_results
        ]
        return PlaceSearchResponse(
            query="nearby", source="google_places", count=len(items), items=items, fallback=False
        )

    rows = list(
        session.exec(
            select(Experience)
            .order_by(Experience.rating.desc())
            .limit(limit)
        ).all()
    )
    rows.sort(key=lambda e: haversine_km(lat, lng, e.lat, e.lng))
    items_local = []
    for exp in rows:
        distance_km = round(haversine_km(lat, lng, exp.lat, exp.lng), 2)
        items_local.append(
            PlaceSearchResult(
                id=str(exp.id),
                name=exp.name,
                category=exp.category,
                address="",
                description=exp.description,
                lat=exp.lat,
                lng=exp.lng,
                rating=exp.rating,
                review_count=0,
                avg_cost=exp.avg_cost,
                image_url=exp.image_url or None,
                open_time=exp.open_time,
                close_time=exp.close_time,
                open_now=None,
                distance_km=distance_km,
                travel_minutes=estimate_travel_time_min(distance_km),
                source="sqlite",
            )
        )
    return PlaceSearchResponse(
        query="nearby", source="sqlite", count=len(items_local), items=items_local, fallback=True
    )


@router.get("/images/place", summary="Proxy a Google place photo")
async def place_photo(
    name: str = Query(..., min_length=1, description="Google photo resource name"),
    width: int = Query(default=800, ge=100, le=1600),
):
    """Stream a Google photo through the backend.

    This is what keeps the server key off the wire: the client only ever talks to
    LocalIQ. Returns 404 when Google is unavailable so the UI can fall back to
    its own placeholder artwork.
    """
    fetched = await google_places.fetch_photo(name, max_width_px=width)
    if fetched is None:
        return Response(status_code=404, content=b"")
    body, content_type = fetched
    return Response(
        content=body,
        media_type=content_type,
        headers={"Cache-Control": "public, max-age=86400"},
    )


@router.get("/integrations/status", summary="Google integration health")
async def integrations_status():
    """Which Google features are live right now. Never fails."""
    return {
        "places": await google_places.google_health(),
        "routes": await google_routes.google_health(),
        "fallback": "sqlite+haversine",
    }
