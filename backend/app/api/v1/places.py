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
import time

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlmodel import Session, select

from app.database import get_session
from app.models import Experience
from app.schemas import PlaceSearchResponse, PlaceSearchResult
from app.config import get_settings
from app.services import google_places, google_routes
from app.services.cache import TTLCache
from app.services.recommender import estimate_travel_time_min, haversine_km

logger = logging.getLogger(__name__)
router = APIRouter()


# ---------------------------------------------------------------------------
# Search cache
# ---------------------------------------------------------------------------
# Typing in the search box repeats the same query, and every miss costs a Google
# Places round-trip (~1.2s measured). Identical searches inside the TTL are
# served from memory instead.

_settings = get_settings()
_places_cache = TTLCache(
    maxsize=_settings.places_cache_maxsize,
    ttl_seconds=_settings.places_cache_ttl_seconds,
)


def clear_places_cache() -> None:
    """Drop cached place searches (used by tests)."""
    _places_cache.clear()


def places_cache_stats() -> dict[str, int]:
    return _places_cache.stats()


def _search_cache_key(
    q: str, lat: float | None, lng: float | None, radius_m: int, limit: int
) -> str:
    return f"{q.strip().lower()}|{lat}|{lng}|{radius_m}|{limit}"



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
    cache_key = _search_cache_key(q, lat, lng, radius_m, limit)
    if _settings.places_cache_enabled:
        cached = _places_cache.get(cache_key)
        if cached is not None:
            logger.debug("places cache hit for %r", q)
            return cached

    response = await _search(q, lat, lng, radius_m, limit, session)
    if _settings.places_cache_enabled:
        _places_cache.set(cache_key, response)
    return response


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


_status_cache: dict[str, object] = {"at": 0.0, "payload": None}


def clear_integrations_status_cache() -> None:
    """Force the next /integrations/status call to re-probe (used by tests)."""
    _status_cache["at"] = 0.0
    _status_cache["payload"] = None


@router.get("/integrations/status", summary="Google integration health")
async def integrations_status(refresh: bool = False):
    """Which Google features are live.

    Probing Google costs two network round-trips, so the result is cached for
    ``integrations_cache_ttl_seconds``. Pass ``?refresh=true`` to force a
    re-probe. Never fails: the payload always reports the fallback chain.
    """
    now = time.monotonic()
    ttl = get_settings().integrations_cache_ttl_seconds
    if (
        not refresh
        and _status_cache["payload"] is not None
        and (now - float(_status_cache["at"])) < ttl
    ):
        payload = dict(_status_cache["payload"])  # type: ignore[arg-type]
        payload["cached"] = True
        return payload

    payload = {
        "places": await google_places.google_health(),
        "routes": await google_routes.google_health(),
        "fallback": "sqlite+haversine",
        "cached": False,
        "ttl_seconds": ttl,
    }
    _status_cache["at"] = now
    _status_cache["payload"] = payload
    return payload
