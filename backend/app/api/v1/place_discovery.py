"""Place-first discovery endpoints for the Flutter app.

The app models discovery as ``Place -> Experience`` (one venue, many activities)
while our dataset is a flat ``Experience`` row per venue+activity. This router
projects each row onto both app shapes (see ``app.services.places``) so the
existing client repositories can talk to the backend unchanged:

    GET /places?text=&lat=&lng=&radius_km=&categories=&limit=&offset=
    GET /places/popular?lat=&lng=&radius_km=&limit=
    GET /places/gems?lat=&lng=&radius_km=&limit=
    GET /places/discover?text=...
    GET /places/{id}
    GET /places/{id}/experiences

Complements ``app.api.v1.places`` (the Google Places integration: ``/places/search``,
``/places/nearby``, ``/images/place``). That router is registered first, so its
static paths win over this router's ``/places/{id}``.

Responses use camelCase keys (matching the Dart mappers) and absolute image URLs.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlmodel import Session

from app.config import get_settings
from app.database import get_session
from app.models import Experience, User
from app.rate_limit import PUBLIC_LIMIT, limiter
from app.services import graphs
from app.services import places as places_service
from app.services.auth import get_current_user_optional
from app.services.weather import fetch_sun_times, fetch_weather, neutral_weather

logger = logging.getLogger(__name__)
router = APIRouter()


def _base_url(request: Request) -> str:
    """Public origin for absolute URLs, falling back to this request's host.

    Behind the tunnel the incoming Host is an internal service name (``backend``)
    absorbed by Kong, so a configured ``PUBLIC_BASE_URL`` is what makes image
    URLs reachable from a device.
    """
    configured = get_settings().public_base_url.strip().rstrip("/")
    if configured:
        return configured
    return str(request.base_url).rstrip("/")


def _as_int(place_id: str) -> int | None:
    try:
        return int(place_id)
    except (TypeError, ValueError):
        return None


def _hhmm(value: str | None) -> str | None:
    """Accept ``18:30`` or a full ISO timestamp and return ``HH:MM``."""
    if not value:
        return None
    if "T" in value:
        value = value.split("T", 1)[1]
    return value[:5]


def _get(session: Session, place_id: str) -> Experience:
    numeric = _as_int(place_id)
    experience = session.get(Experience, numeric) if numeric is not None else None
    if experience is None:
        raise HTTPException(status_code=404, detail="Place not found")
    return experience


# ---------------------------------------------------------------------------
# Static routes first so they are not captured by /places/{place_id}
# ---------------------------------------------------------------------------


@router.get("/places/popular", summary="Popular places near a point")
@limiter.limit(PUBLIC_LIMIT)
def popular_places(
    request: Request,
    response: Response,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(default=6.0, gt=0, le=50),
    limit: int = Query(default=12, ge=1, le=50),
    session: Session = Depends(get_session),
):
    base = _base_url(request)
    rows = places_service.popular(
        session, lat=lat, lng=lng, radius_km=radius_km, limit=limit
    )
    return [places_service.place_from_experience(e, base=base) for e in rows]


@router.get("/places/gems", summary="Local-gem places near a point")
@limiter.limit(PUBLIC_LIMIT)
def gem_places(
    request: Request,
    response: Response,
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=8.0, gt=0, le=50),
    limit: int = Query(default=12, ge=1, le=50),
    session: Session = Depends(get_session),
):
    """Genuine hidden gems, ranked by local-gem score.

    Omit ``lat``/``lng`` for a city-wide list; pass them to restrict to nearby
    finds. Only venues above the gem floor are returned.
    """
    base = _base_url(request)
    rows = places_service.gems(
        session, lat=lat, lng=lng, radius_km=radius_km, limit=limit
    )
    return [places_service.place_from_experience(e, base=base) for e in rows]


async def _conditions(lat: float | None, lng: float | None) -> tuple[dict, dict]:
    """Weather + sun times, never failing the request."""
    try:
        if lat is not None and lng is not None:
            weather = await fetch_weather(lat, lng)
            sun = await fetch_sun_times(lat, lng)
        else:
            weather = await fetch_weather()
            sun = await fetch_sun_times()
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Place feed conditions lookup failed: %s", exc)
        weather = neutral_weather(reason="exception")
        sun = {"available": False}
    return weather, sun


@router.get("/places/for-you", summary="Personalized places (taste-ranked)")
@limiter.limit(PUBLIC_LIMIT)
async def for_you_places(
    request: Request,
    response: Response,
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    limit: int = Query(default=12, ge=1, le=30),
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """Recommendations ranked by the signed-in user's learned taste vector.

    Anonymous callers (no token) get the deterministic feasibility ranking, so
    the rail is never empty and never blocked on auth.
    """
    base = _base_url(request)
    weather, _sun = await _conditions(lat, lng)
    ranked = graphs.taste_aware_recommend(
        session,
        current_user,
        lat=lat,
        lng=lng,
        weather=weather,
        limit=limit,
    )
    return [places_service.place_from_experience(r.experience, base=base) for r in ranked]


@router.get("/places/right-now", summary="Live 'Right Now' places (weather + crowd + time)")
@limiter.limit(PUBLIC_LIMIT)
async def right_now_places(
    request: Request,
    response: Response,
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    limit: int = Query(default=12, ge=1, le=30),
    session: Session = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    """The moment's best places, ranked by weather, time-of-day and crowd.

    Each card carries ``rightNowLabel`` / ``rightNowContext`` computed for this
    request, so the UI shows the real reason instead of a fixed badge. Ranked
    independently of the taste reranker so it never mirrors "Recommended".
    """
    base = _base_url(request)
    weather, sun = await _conditions(lat, lng)
    scored = places_service.right_now_ranked(
        session,
        weather=weather,
        sun=sun,
        lat=lat,
        lng=lng,
        radius_km=12.0 if (lat is not None and lng is not None) else None,
        limit=limit,
    )
    return [
        places_service.place_from_experience(exp, base=base, right_now=result)
        for result, exp in scored
    ]


@router.get("/places/discover", summary="Natural-language place discovery")
@limiter.limit(PUBLIC_LIMIT)
def discover_places(
    request: Request,
    response: Response,
    text: str | None = Query(default=None),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=12.0, gt=0, le=50),
    categories: list[str] | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=60),
    max_spend: int | None = Query(default=None, ge=0),
    session: Session = Depends(get_session),
):
    """Ranked places + experiences for a free-text query."""
    base = _base_url(request)
    rows = places_service.search(
        session,
        text=text,
        lat=lat,
        lng=lng,
        radius_km=radius_km,
        categories=categories,
        limit=limit,
        max_spend=max_spend,
    )
    return {
        "places": [places_service.place_from_experience(e, base=base) for e in rows],
        "experiences": [
            places_service.experience_from_experience(e, base=base) for e in rows
        ],
        "interpreted_query": (text or "").strip() or None,
    }


# ---------------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------------


@router.get("/places", summary="List places with filters")
@limiter.limit(PUBLIC_LIMIT)
def list_places(
    request: Request,
    response: Response,
    text: str | None = Query(default=None),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=12.0, gt=0, le=50),
    categories: list[str] | None = Query(default=None),
    limit: int = Query(default=40, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    open_at: str | None = Query(default=None),
    max_spend: int | None = Query(default=None, ge=0),
    session: Session = Depends(get_session),
):
    base = _base_url(request)
    rows = places_service.search(
        session,
        text=text,
        lat=lat,
        lng=lng,
        radius_km=radius_km,
        categories=categories,
        limit=limit,
        offset=offset,
        open_at=_hhmm(open_at),
        max_spend=max_spend,
    )
    return [places_service.place_from_experience(e, base=base) for e in rows]


# ---------------------------------------------------------------------------
# Detail
# ---------------------------------------------------------------------------


@router.get("/places/{place_id}", summary="Place detail")
@limiter.limit(PUBLIC_LIMIT)
def get_place(
    request: Request,
    response: Response,
    place_id: str,
    session: Session = Depends(get_session),
):
    base = _base_url(request)
    return places_service.place_from_experience(_get(session, place_id), base=base)


@router.get("/places/{place_id}/experiences", summary="Experiences at a place")
@limiter.limit(PUBLIC_LIMIT)
def get_place_experiences(
    request: Request,
    response: Response,
    place_id: str,
    session: Session = Depends(get_session),
):
    base = _base_url(request)
    return [
        places_service.experience_from_experience(_get(session, place_id), base=base)
    ]
